// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract ETHInsurancePool {
    /// @notice The address allowed to purchase insurance.
    address public authorizedToPurchaseContract;

    /// @notice The address allowed to execute reimbursements.
    address public authorizedToReimburseContract;

    /// @notice Structure representing an insurance policy.
    struct Insurance {
        uint256 depositAmount; // The ETH deposited by the client.
        uint256 securedAmount; // The maximum ETH that can be reimbursed.
        uint256 expirationTime; // Timestamp until which the insurance is valid.
        bool valid; // True if the insurance has not yet been executed.
    }

    /// @notice Mapping from client address to their list of insurances.
    mapping(address => Insurance[]) public insurances;

    /// @notice Emitted when a new insurance is created.
    event InsuranceCreated(
        address indexed client,
        uint256 insuranceId,
        uint256 depositAmount,
        uint256 securedAmount,
        uint256 expirationTime
    );

    /// @notice Emitted when a reimbursement is executed.
    event Reimbursed(
        address indexed client,
        uint256 insuranceId,
        uint256 amount
    );

    /// @notice Modifier to restrict function calls to only the authorized contract for buying insurance.
    modifier onlyAuthorizedToBuy() {
        require(
            msg.sender == authorizedToPurchaseContract,
            "Not authorized to buy"
        );
        _;
    }

    /// @notice Modifier to restrict function calls to only the authorized contract.
    modifier onlyAuthorizedToReimburse() {
        require(msg.sender == authorizedToReimburseContract, "Not authorized");
        _;
    }

    /// @notice Sets the authorized contracts that can call reimburse and buy insurance.
    /// @param _authorizedToPurchaseContract The address of the contract allowed to buy insurance.
    /// @param _authorizedToReimburseContract The address of the contract allowed to call reimburse.
    constructor(
        address _authorizedToPurchaseContract,
        address _authorizedToReimburseContract
    ) {
        authorizedToPurchaseContract = _authorizedToPurchaseContract;
        authorizedToReimburseContract = _authorizedToReimburseContract;
    }

    /// @notice Allows users to buy an insurance policy by sending ETH.
    /// @param securedAmount The maximum amount of ETH that will be covered.
    /// @dev The caller must send ETH with this transaction (as msg.value).
    function buyInsurance(
        uint256 securedAmount
    ) external payable onlyAuthorizedToBuy {
        require(msg.value > 0, "Must send ETH to buy insurance");

        // Calculate the expiration time as one year from now.
        uint256 expirationTime = block.timestamp + 365 days;

        // Create a new insurance record.
        Insurance memory newInsurance = Insurance({
            depositAmount: msg.value,
            securedAmount: securedAmount,
            expirationTime: expirationTime,
            valid: true
        });

        // Store the new insurance in the caller's list.
        insurances[msg.sender].push(newInsurance);
        // Insurance IDs are 1-indexed (first insurance gets ID 1, etc.).
        uint256 insuranceId = insurances[msg.sender].length;
        emit InsuranceCreated(
            msg.sender,
            insuranceId,
            msg.value,
            securedAmount,
            expirationTime
        );
    }

    /// @notice Executes a reimbursement to a client based on their insurance.
    /// @param amount The amount of ETH to send.
    /// @param client The address of the client receiving the reimbursement.
    /// @param insuranceId The ID of the insurance policy to consider.
    /// @dev Only the authorized contract can call this function.
    function reimburse(
        uint256 amount,
        address client,
        uint256 insuranceId
    ) external onlyAuthorizedToReimburse {
        require(
            insuranceId > 0 && insuranceId <= insurances[client].length,
            "Invalid insurance ID"
        );

        // Get the insurance record (IDs are 1-indexed, array index is insuranceId - 1).
        Insurance storage insurance = insurances[client][insuranceId - 1];

        require(insurance.valid, "Insurance already used");
        require(
            block.timestamp <= insurance.expirationTime,
            "Insurance expired"
        );
        require(
            amount <= insurance.securedAmount,
            "Amount exceeds secured limit"
        );
        require(address(this).balance >= amount, "Insufficient pool balance");

        // Mark the insurance as used before transferring to prevent reentrancy.
        insurance.valid = false;

        // Transfer ETH to the client.
        (bool success, ) = client.call{value: amount}("");
        require(success, "Transfer failed");

        emit Reimbursed(client, insuranceId, amount);
    }
}
