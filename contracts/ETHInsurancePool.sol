// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract ETHInsurancePool {
    /// @notice The address allowed to purchase insurance.
    address public authorizedToPurchaseContract;

    /// @notice The address allowed to execute reimbursements.
    address public authorizedToReimburseContract;

    /// @notice The total amount currently covered by active insurances.
    uint256 public totalSecuredAmount;

    /// @notice Structure representing an insurance policy.
    struct Insurance {
        uint256 depositAmount; // The ETH deposited by the client (i.e. the premium).
        uint256 securedAmount; // The maximum ETH that can be reimbursed.
        uint256 expirationTime; // Timestamp until which the insurance is valid.
        bool valid; // True if the insurance has not yet been executed.
        string ipfsCid; // IPFS CID of the insurance details document.
    }

    /// @notice Mapping from client address to their list of insurances.
    mapping(address => Insurance[]) public insurances;

    /// @notice Emitted when a new insurance is created.
    event InsuranceCreated(
        address indexed client,
        uint256 insuranceId,
        uint256 depositAmount,
        uint256 securedAmount,
        uint256 expirationTime,
        string ipfsCid
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

    /// @notice Modifier to restrict function calls to only the authorized contract for reimbursements.
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

    /// @notice Allows users to buy an insurance policy by sending ETH as premium.
    /// @param securedAmount The maximum amount of ETH that will be covered.
    /// @param ipfsCid The IPFS CID of the document containing insurance details.
    /// @dev The caller must send ETH with this transaction (as msg.value), and msg.value should equal the calculated premium.
    function buyInsurance(
        uint256 securedAmount,
        string calldata ipfsCid
    ) external payable onlyAuthorizedToBuy {
        require(msg.value > 0, "Must send ETH as premium");

        // Calculate the expiration time as one year from now.
        uint256 expirationTime = block.timestamp + 365 days;

        // Create a new insurance record.
        Insurance memory newInsurance = Insurance({
            depositAmount: msg.value,
            securedAmount: securedAmount,
            expirationTime: expirationTime,
            valid: true,
            ipfsCid: ipfsCid
        });

        // Store the new insurance in the caller's list.
        insurances[msg.sender].push(newInsurance);
        uint256 insuranceId = insurances[msg.sender].length - 1;

        // Increase the total covered amount.
        totalSecuredAmount += securedAmount;

        emit InsuranceCreated(
            msg.sender,
            insuranceId,
            msg.value,
            securedAmount,
            expirationTime,
            ipfsCid
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
            insuranceId < insurances[client].length,
            "Invalid insurance ID"
        );

        // Get the insurance record.
        Insurance storage insurance = insurances[client][insuranceId];

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

        // Mark the insurance as used and remove its exposure.
        insurance.valid = false;
        totalSecuredAmount -= insurance.securedAmount;

        // Transfer ETH to the client.
        (bool success, ) = client.call{value: amount}("");
        require(success, "Transfer failed");

        emit Reimbursed(client, insuranceId, amount);
    }

    /// @notice Calculates the premium for an insurance contract based on the amount to be covered.
    /// @param securedAmount The maximum coverage amount requested.
    /// @return premium The calculated premium.
    ///
    /// The formula used is:
    /// premium = securedAmount + (securedAmount * totalSecuredAmount) / (treasury + securedAmount)
    ///
    /// This formula loads the premium upward when the pool’s exposure (totalSecuredAmount) is high relative
    /// to its treasury (the contract's balance). When the pool is well-funded compared to its active coverages,
    /// the premium will be closer to the coverage amount.
    function calculatePremium(
        uint256 securedAmount
    ) public view onlyAuthorizedToBuy returns (uint256) {
        uint256 treasury = address(this).balance;
        // The risk loading is higher if total exposure is high relative to available treasury.
        uint256 riskLoading = (securedAmount * totalSecuredAmount) /
            (treasury + securedAmount);
        return securedAmount + riskLoading;
    }
}
