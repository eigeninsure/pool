// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract ETHInsurancePool {
    /// @notice The address allowed to create insurance.
    address public authorizedToCreateContract;

    /// @notice The address allowed to execute reimbursements.
    address public authorizedToReimburseContract;

    /// @notice The total amount currently covered by active insurances.
    uint256 public totalSecuredAmount;

    /// @notice Structure representing an insurance policy.
    struct Insurance {
        uint256 depositAmount; // The ETH deposited by the client (i.e. the premium).
        uint256 securedAmount; // The maximum ETH that can be reimbursed.
        uint256 expirationTime; // Timestamp until which the insurance is valid.
        bool activated; // True if the insurance has been activated.
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
        bool activated,
        bool valid,
        string ipfsCid
    );

    /// @notice Emitted when a reimbursement is executed.
    event Reimbursed(
        address indexed client,
        uint256 insuranceId,
        uint256 amount
    );

    /// @notice Modifier to restrict function calls to only the authorized contract for creating insurances.
    modifier onlyAuthorizedToCreateContract() {
        require(
            msg.sender == authorizedToCreateContract,
            "Not authorized to buy"
        );
        _;
    }

    /// @notice Modifier to restrict function calls to only the authorized contract for reimbursements.
    modifier onlyAuthorizedToReimburse() {
        require(msg.sender == authorizedToReimburseContract, "Not authorized");
        _;
    }

    /// @notice Sets the authorized contracts that can call create and reimburse insurance.
    /// @param _authorizedToCreateContract The address of the contract allowed to call create.
    /// @param _authorizedToReimburseContract The address of the contract allowed to call reimburse.
    constructor(
        address _authorizedToCreateContract,
        address _authorizedToReimburseContract
    ) {
        authorizedToCreateContract = _authorizedToCreateContract;
        authorizedToReimburseContract = _authorizedToReimburseContract;
    }

    /// @notice Allows the authorized contract to create an insurance policy for a client without activating it.
    /// @param client The address of the client for whom the insurance is being created.
    /// @param depositAmount The amount of ETH initially deposited.
    /// @param securedAmount The maximum amount of ETH that will be covered.
    /// @param ipfsCid The IPFS CID of the document containing insurance details.
    /// @return insuranceId The ID of the created insurance.
    function createInsurance(
        address client,
        uint256 depositAmount,
        uint256 securedAmount,
        string calldata ipfsCid
    ) external onlyAuthorizedToCreateContract returns (uint256 insuranceId) {
        // Calculate the expiration time as one year from now.
        uint256 expirationTime = block.timestamp + 365 days;
        bool activated = false;
        bool valid = true;

        // Create a new insurance record.
        Insurance memory newInsurance = Insurance({
            depositAmount: depositAmount, // Take deposit amount as a parameter.
            securedAmount: securedAmount,
            expirationTime: expirationTime,
            activated: activated, // Not activated initially.
            valid: valid,
            ipfsCid: ipfsCid
        });

        // Store the new insurance in the client's list.
        insurances[client].push(newInsurance);
        insuranceId = insurances[client].length - 1;

        emit InsuranceCreated(
            client,
            insuranceId,
            depositAmount,
            securedAmount,
            expirationTime,
            activated,
            valid,
            ipfsCid
        );
    }

    /// @notice Activates an existing insurance policy by sending ETH as premium.
    /// @param insuranceId The ID of the insurance to activate.
    /// @dev The caller must send ETH with this transaction (as msg.value), and msg.value should be greater than the depositAmount.
    function activateInsurance(uint256 insuranceId) external payable {
        require(
            insuranceId < insurances[msg.sender].length,
            "Invalid insurance ID"
        );

        // Get the insurance record.
        Insurance storage insurance = insurances[msg.sender][insuranceId];

        require(!insurance.activated, "Insurance already activated");
        require(msg.value > insurance.depositAmount, "Insufficient ETH sent");

        // Activate the insurance.
        insurance.depositAmount = msg.value;
        insurance.activated = true;

        // Increase the total covered amount.
        totalSecuredAmount += insurance.securedAmount;

        // Calculate the excess amount to return.
        uint256 excessAmount = msg.value - insurance.depositAmount;

        // Return the excess ETH to the sender.
        if (excessAmount > 0) {
            (bool success, ) = msg.sender.call{value: excessAmount}("");
            require(success, "Transfer of excess ETH failed");
        }

        emit InsuranceCreated(
            msg.sender,
            insuranceId,
            msg.value,
            insurance.securedAmount,
            insurance.expirationTime,
            true,
            insurance.valid,
            insurance.ipfsCid
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
    ) public view onlyAuthorizedToCreateContract returns (uint256) {
        uint256 treasury = address(this).balance;
        // The risk loading is higher if total exposure is high relative to available treasury.
        uint256 riskLoading = (securedAmount * totalSecuredAmount) /
            (treasury + securedAmount);
        return securedAmount + riskLoading;
    }
}
