const { ethers } = require("hardhat");

async function main() {
    const [deployer, consumer, provider, verifier1, verifier2, verifier3, verifier4, verifier5, verifier6, verifier7] = await ethers.getSigners();

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
    console.log("COMP Token deployed to:", compToken.address);
    console.log("Computation Market deployed to:", market.address);

    // Distribute COMP tokens to test accounts
    const amount = ethers.utils.parseUnits("1000000", 18); // 1 million COMP tokens
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

    // Interact with the deployed contracts
    const paymentForProvider = ethers.utils.parseUnits("1000", 18);
    const paymentPerRoundForVerifiers = ethers.utils.parseUnits("500", 18);
    const totalPaymentForVerifiers = paymentPerRoundForVerifiers.mul(3 * 5);
    const totalPayment = paymentForProvider.add(totalPaymentForVerifiers);

    // Consumer approves the market contract to spend their tokens
    await compToken.connect(consumer).approve(market.address, totalPayment);
    console.log("Consumer approved tokens for market");

    // Consumer creates a request
    await market.connect(consumer).createRequest(
        paymentForProvider,
        paymentPerRoundForVerifiers,
        3000,
        7,
        ["https://example.com/input"],
        "https://example.com/operation",
        86400,
        172800,
        3600,
        5
    );
    console.log("Request created by consumer");

    // Provider approves and selects the request
    await compToken.connect(provider).approve(market.address, paymentForProvider);
    await market.connect(provider).selectRequest(0);
    console.log("Request selected by provider");

    // Provider completes the request
    await market.connect(provider).completeRequest(0, ["https://example.com/output"]);
    console.log("Request completed by provider");

    // Verifiers apply for verification and submit commitments
    const verifierAccounts = [verifier1, verifier2, verifier3, verifier4, verifier5, verifier6, verifier7];
    for (let i = 0; i < verifierAccounts.length; i++) {
        await compToken.connect(verifierAccounts[i]).approve(market.address, paymentPerRoundForVerifiers);
        await market.connect(verifierAccounts[i]).applyForVerificationForRequest(0);
    }
    console.log("Verifiers applied for verification");

    const chosenVerifiers = await market.getChosenVerifiers(0);
    for (let i = 0; i < chosenVerifiers.length; i++) {
        const verifier = verifierAccounts.find(v => v.address === chosenVerifiers[i]);
        const computedHash = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(
            ["bool", "bytes32", "bytes32", "address"],
            [true, ethers.utils.keccak256(ethers.utils.toUtf8Bytes("answer")), ethers.utils.keccak256(ethers.utils.toUtf8Bytes("nonce")), chosenVerifiers[i]]
        ));
        await market.connect(verifier).submitCommitment(0, computedHash);
    }
    console.log("Verifiers submitted commitments");

    // Provider reveals key and hash
    await market.connect(provider).revealProviderKeyAndHash(0, ethers.utils.keccak256(ethers.utils.toUtf8Bytes("private_key")), ethers.utils.keccak256(ethers.utils.toUtf8Bytes("answer")));
    console.log("Provider revealed key and hash");

    // Verifiers reveal commitments
    for (let i = 0; i < chosenVerifiers.length; i++) {
        const verifier = verifierAccounts.find(v => v.address === chosenVerifiers[i]);
        await market.connect(verifier).revealCommitment(0, true, ethers.utils.keccak256(ethers.utils.toUtf8Bytes("answer")), ethers.utils.keccak256(ethers.utils.toUtf8Bytes("nonce")));
    }
    console.log("Verifiers revealed commitments");

    // Calculate majority and distribute rewards
    await market.calculateMajorityAndReward(0);
    console.log("Majority calculated and rewards distributed");

    // Repeat the verification process for multiple rounds
    for (let round = 1; round <= 3; round++) {
        console.log(`Starting round ${round}`);
        const newChosenVerifiers = await market.getChosenVerifiers(0);
        for (let i = 0; i < newChosenVerifiers.length; i++) {
            const verifier = verifierAccounts.find(v => v.address === newChosenVerifiers[i]);
            const computedHash = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(
                ["bool", "bytes32", "bytes32", "address"],
                [true, ethers.utils.keccak256(ethers.utils.toUtf8Bytes("answer")), ethers.utils.keccak256(ethers.utils.toUtf8Bytes("nonce")), newChosenVerifiers[i]]
            ));
            await market.connect(verifier).submitCommitment(0, computedHash);
        }
        console.log("Verifiers submitted commitments again");

        await market.connect(provider).revealProviderKeyAndHash(0, ethers.utils.keccak256(ethers.utils.toUtf8Bytes("private_key")), ethers.utils.keccak256(ethers.utils.toUtf8Bytes("answer")));
        console.log("Provider revealed key and hash again");

        for (let i = 0; i < newChosenVerifiers.length; i++) {
            const verifier = verifierAccounts.find(v => v.address === newChosenVerifiers[i]);
            await market.connect(verifier).revealCommitment(0, true, ethers.utils.keccak256(ethers.utils.toUtf8Bytes("answer")), ethers.utils.keccak256(ethers.utils.toUtf8Bytes("nonce")));
        }
        console.log("Verifiers revealed commitments again");

        await market.calculateMajorityAndReward(0);
        console.log(`Majority calculated and rewards distributed for round ${round}`);
    }

    console.log("Completed all rounds successfully");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
