async function main() {
    // Get the deployer's account.
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);
    console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

    // Set the addresses for the authorized contracts.
    const authorizedToPurchaseContract = "0x2007c3373D6B737A6b9C6E9CbC795843B6E46fb1";
    const authorizedToReimburseContract = "0x2007c3373D6B737A6b9C6E9CbC795843B6E46fb1";

    // Get the contract factory.
    const ETHInsurancePool = await ethers.getContractFactory("ETHInsurancePool");

    // Deploy the contract.
    const insurancePool = await ETHInsurancePool.deploy(
        authorizedToPurchaseContract,
        authorizedToReimburseContract
    );
    await insurancePool.waitForDeployment();

    console.log("ETHInsurancePool deployed to:", await insurancePool.getAddress());
}

// Execute the main function.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("Error during deployment:", error);
        process.exit(1);
    });
