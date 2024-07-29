const { ethers } = require("hardhat");

async function main() {
    const [deployer, consumer, provider, verifier1, verifier2, verifier3, verifier4, verifier5, verifier6, verifier7] = await ethers.getSigners();
    const privateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

    // Deploy the COMP token with initial supply
    const initialSupply = ethers.utils.parseUnits("1000000000000", 18); // 1 trillion COMP tokens
    const MockERC20 = await ethers.getContractFactory("COMPToken");
    const compToken = await MockERC20.deploy(initialSupply);
    await compToken.deployed();

    // Deploy the ComputationMarket contract
    const ComputationMarket = await ethers.getContractFactory("ComputationMarket");
    const market = await ComputationMarket.deploy(compToken.address);
    await market.deployed();

    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Using private key:", privateKey);
    console.log("COMP Token deployed to:", compToken.address);
    console.log("Computation Market deployed to:", market.address);

    // Distribute COMP tokens to test accounts
    const amount = ethers.utils.parseUnits("1000000000000000000000000", 18); // 1 million COMP tokens
    const txs = [
        compToken.transfer(consumer.address, amount),
        compToken.transfer(provider.address, amount),
        compToken.transfer(verifier1.address, amount),
        compToken.transfer(verifier2.address, amount),
        compToken.transfer(verifier3.address, amount),
        compToken.transfer(verifier4.address, amount),
        compToken.transfer(verifier5.address, amount),
        compToken.transfer(verifier6.address, amount),
        compToken.transfer(verifier7.address, amount)
    ];

    await Promise.all(txs);

    console.log("Tokens distributed");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
