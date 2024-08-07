// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/ComputationMarket.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock COMP Token", "COMP") {
        _mint(msg.sender, 1000000000000000000000000000 * 10 ** decimals());
    }
}

contract ComputationMarketTest is Test {
    ComputationMarket public market;
    MockERC20 public compToken;
    CompNFT public compNFT;
    HandlerFunctionsCompMarket public handler;

    address consumer = address(1);
    address provider = address(2);
    address verifier1 = address(3);
    address verifier2 = address(4);
    address verifier3 = address(5);

    uint256 paymentForProvider = 20;
    uint256 paymentPerRoundForVerifiers = 5;
    uint256 totalPaymentForVerifiers;
    uint256 numOperations = 3000;
    uint256 numVerifiers = 3;
    uint256 computationDeadline = 1 days;
    uint256 verificationDeadline = 2 days;
    uint256 timeAllocatedForVerification = 1 hours;
    uint256 numVerifiersSampleSize = 3; // For testing purposes
    uint256 constant PROVIDER_STAKE_PERCENTAGE = 50;

    function setUp() public {
        // Deploy the mock COMP token and the market contract
        compToken = new MockERC20();
        compNFT = new CompNFT();
        handler = new HandlerFunctionsCompMarket();
        market = new ComputationMarket(address(compToken), address(compNFT), address(handler));
        compNFT.transferNFTContractOwnership(address(market));

        // Distribute COMP tokens to test accounts
        distributeTokens();

        // Label accounts for better readability in logs
        labelAccounts();

        // Calculate total payment for verifiers
        uint256 layerCount = (numOperations + 999) / 1000;
        totalPaymentForVerifiers = paymentPerRoundForVerifiers * numVerifiersSampleSize * layerCount;
    }

    function distributeTokens() internal {
        compToken.transfer(consumer, 1000);
        compToken.transfer(provider, 1000);
        compToken.transfer(verifier1, 1000);
        compToken.transfer(verifier2, 1000);
        compToken.transfer(verifier3, 1000);
    }

    function labelAccounts() internal {
        vm.label(consumer, "Consumer");
        vm.label(provider, "Provider");
        vm.label(verifier1, "Verifier1");
        vm.label(verifier2, "Verifier2");
        vm.label(verifier3, "Verifier3");
    }

    function approveTokens(address user, uint256 amount) internal {
        vm.startPrank(user);
        compToken.approve(address(market), amount);
        vm.stopPrank();
    }

    function createTestRequest() internal {
        vm.startPrank(consumer);
        uint256 totalPayment = paymentForProvider + totalPaymentForVerifiers;
        compToken.approve(address(market), totalPayment);
        string[] memory inputFileURLs = new string[](1);
        inputFileURLs[0] = "input_file_url";
        market.createRequest(
            paymentForProvider,
            paymentPerRoundForVerifiers,
            numOperations,
            numVerifiers,
            inputFileURLs,
            "operation_file_url",
            block.timestamp + computationDeadline,
            block.timestamp + verificationDeadline,
            timeAllocatedForVerification,
            numVerifiersSampleSize,
            1,
            1000,
            bytes32(0),
            paymentForProvider * PROVIDER_STAKE_PERCENTAGE / 100
        );
        vm.stopPrank();
    }

    function selectTestRequest() internal {
        createTestRequest();

        vm.startPrank(provider);
        uint256 stakeAmount = (paymentForProvider * PROVIDER_STAKE_PERCENTAGE) / 100;
        compToken.approve(address(market), stakeAmount);
        market.selectRequest(0);
        vm.stopPrank();
    }

    function completeTestRequest() internal {
        selectTestRequest();

        vm.startPrank(provider);
        string[] memory outputFileURLs = new string[](1);
        outputFileURLs[0] = "output_file_url";
        market.completeRequest(0, outputFileURLs);
        vm.warp(block.timestamp + 6);
        vm.stopPrank();
    }

    function applyForVerification(address verifierAddress) internal {
        approveTokens(verifierAddress, paymentPerRoundForVerifiers);
        vm.startPrank(verifierAddress);
        market.applyForVerificationForRequest(0);
        vm.stopPrank();
    }

    function triggerVerification(address verifierAddress) internal {
        vm.startPrank(verifierAddress);
        market.chooseVerifiersForRequestTrigger(0);
        vm.stopPrank();
    }

    function submitCommitment(address verifierAddress, bytes32 computedHash) internal {
        vm.startPrank(verifierAddress);
        market.submitCommitment(0, computedHash);
        vm.stopPrank();
    }

    function revealProviderKeyAndHash(uint256 privateKey, bytes32 answerHash) internal {
        vm.startPrank(provider);
        uint256 initialisationVector = block.timestamp;
        market.revealProviderKeyAndHash(0, privateKey, initialisationVector, answerHash);
        vm.stopPrank();
    }

    function performSuccessfulRound(address v1, address v2, address v3, uint256 roundNum) internal {
        applyForVerification(v1);
        applyForVerification(v2);
        applyForVerification(v3);

        triggerVerification(v1);
        triggerVerification(v2);
        triggerVerification(v3);

        bytes32 computedHash1 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce1")), v1));
        bytes32 computedHash2 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce2")), v2));
        bytes32 computedHash3 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce3")), v3));

        submitCommitment(v1, computedHash1);
        submitCommitment(v2, computedHash2);
        submitCommitment(v3, computedHash3);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key", block.timestamp));
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        revealProviderKeyAndHash(uint256(privateKey), answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        vm.startPrank(v1);
        market.revealCommitment(0, true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce1")));
        vm.stopPrank();

        vm.startPrank(v2);
        market.revealCommitment(0, true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce2")));
        vm.stopPrank();

        vm.startPrank(v3);
        market.revealCommitment(0, false, keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce3")));
        vm.stopPrank();

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        getRewardsAndStakes(verifier1, roundNum);
        getRewardsAndStakes(verifier2, roundNum);
        getRewardsAndStakes(verifier3, roundNum);

        vm.stopPrank();
    }

    function getRewardsAndStakes(address verifier, uint256 roundNum) internal {
        vm.prank(verifier);
        market.calculateMajorityAndReward(0, roundNum);
        vm.stopPrank();
    }

    struct RequestDetails {
        address consumer; // The address of the consumer who created the request
        uint256 paymentForProvider; // Payment allocated for the provider
        uint256 totalPaymentForVerifiers; // Total payment allocated for verifiers
        uint256 numOperations; // Number of operations to be performed
        uint256 numVerifiers; // Number of verifiers needed
        string operationFileURL; // URL of the file with operations
        uint256 computationDeadline; // Deadline for the provider to complete computations
        uint256 verificationDeadline; // Deadline for verifiers to complete verifications
        uint256 totalPayment; // Total payment provided by the consumer
        bool completed; // Indicates if the request is completed. If true, the request has reached the end of its lifecycle
        bool hasBeenComputed; // Indicates if the computation has been completed
        uint256 numVerifiersSampleSize; // Number of verifiers sampled for each round
        address mainProvider; // The provider who accepted the request
        uint256 timeAllocatedForVerification; // Time allocated for each verification round
        uint256 layerCount; // Number of layers of operations
        uint256 layerComputeIndex; // Number of layers computed so far into the DAG
        uint256 roundIndex; // Number of rounds we have performed so far
        ComputationMarket.RequestStates state; // The state of the current request
        uint256 stake; // Amount staked by the provider
        uint256 paymentPerRoundForVerifiers; // Amount the consumer will pay for verification
        uint256 totalPaidForVerification; // Running total of amount paid to verifiers
        uint256 protocolVersion; // Version of the protocol we are following
        uint256 verifierSelectionCount; // Number of verifiers selected for the current round
        uint256 firstinitialisedTime; // Time when the request was first initialised
        uint256 layerSize; // Number of operations that are verified within each of the layers for each round
        bytes32 hashOfInputFiles; // Hash of the input files 
    }

    function getRequestDetails(uint256 requestID) public view returns (RequestDetails memory) {
        (
            address consumer1,
            uint256 paymentForProvider1,
            uint256 totalPaymentForVerifiers1,
            uint256 numOperations1,
            uint256 numVerifiers1,
            string memory operationFileURL1,
            uint256 computationDeadline1,
            uint256 verificationDeadline1,
            uint256 totalPayment1,
            bool completed1,
            bool hasBeenComputed1,
            uint256 numVerifiersSampleSize1,
            address mainProvider1,
            uint256 timeAllocatedForVerification1,
            uint256 layerCount1,
            uint256 layerComputeIndex1,
            uint256 roundIndex1,
            ComputationMarket.RequestStates state1,
            uint256 stake1,
            uint256 paymentPerRoundForVerifiers1,
            uint256 totalPaidForVerification1,
            uint256 protocolVersion1,
            uint256 verifierSelectionCount1,
            uint256 firstinitialisedTime1,
            uint256 layerSize1,
            bytes32 hashOfInputFiles1
        ) = market.requests(requestID);

        return RequestDetails({
            consumer: consumer1,
            paymentForProvider: paymentForProvider1,
            totalPaymentForVerifiers: totalPaymentForVerifiers1,
            numOperations: numOperations1,
            numVerifiers: numVerifiers1,
            operationFileURL: operationFileURL1,
            computationDeadline: computationDeadline1,
            verificationDeadline: verificationDeadline1,
            totalPayment: totalPayment1,
            completed: completed1,
            hasBeenComputed: hasBeenComputed1,
            numVerifiersSampleSize: numVerifiersSampleSize1,
            mainProvider: mainProvider1,
            timeAllocatedForVerification: timeAllocatedForVerification1,
            layerCount: layerCount1,
            layerComputeIndex: layerComputeIndex1,
            roundIndex: roundIndex1,
            state: state1,
            stake: stake1,
            paymentPerRoundForVerifiers: paymentPerRoundForVerifiers1,
            totalPaidForVerification: totalPaidForVerification1,
            protocolVersion: protocolVersion1,
            verifierSelectionCount: verifierSelectionCount1,
            firstinitialisedTime: firstinitialisedTime1,
            layerSize: layerSize1,
            hashOfInputFiles: hashOfInputFiles1
        });

    }

    function testMajorityAgreement() public {
        completeTestRequest();
        RequestDetails memory request = getRequestDetails(0);
        performSuccessfulRound(verifier1, verifier2, verifier3, 1);
        request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
        performSuccessfulRound(verifier1, verifier2, verifier3, 2);
        request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
        performSuccessfulRound(verifier1, verifier2, verifier3, 3);
        request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));
    }

    function testProviderFailureWithNoMajority() public {
        completeTestRequest();
        applyForVerification(verifier1);
        applyForVerification(verifier2);
        applyForVerification(verifier3);

        triggerVerification(verifier1);
        triggerVerification(verifier2);
        triggerVerification(verifier3);

        RequestDetails memory request = getRequestDetails(0);
        bytes32 computedHash1 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("wrong_answer1")), keccak256(abi.encodePacked("nonce1")), verifier1));
        bytes32 computedHash2 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("wrong_answer2")), keccak256(abi.encodePacked("nonce2")), verifier2));
        bytes32 computedHash3 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("wrong_answer3")), keccak256(abi.encodePacked("nonce3")), verifier3));

        submitCommitment(verifier1, computedHash1);
        submitCommitment(verifier2, computedHash2);
        submitCommitment(verifier3, computedHash3);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        revealProviderKeyAndHash(uint256(keccak256(abi.encodePacked(privateKey, bytes32(block.timestamp)))), answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        vm.startPrank(verifier1);
        market.revealCommitment(0, false, keccak256(abi.encodePacked("wrong_answer1")), keccak256(abi.encodePacked("nonce1")));
        vm.stopPrank();

        vm.startPrank(verifier2);
        market.revealCommitment(0, false, keccak256(abi.encodePacked("wrong_answer2")), keccak256(abi.encodePacked("nonce2")));
        vm.stopPrank();

        vm.startPrank(verifier3);
        market.revealCommitment(0, false, keccak256(abi.encodePacked("wrong_answer3")), keccak256(abi.encodePacked("nonce3")));
        vm.stopPrank();

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        getRewardsAndStakes(verifier1, 1);
        getRewardsAndStakes(verifier2, 1);
        getRewardsAndStakes(verifier3, 1);

        request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
        assertEq(request.completed, false);
    }

    function testVerifierMajorityFailure() public {
        completeTestRequest();
        applyForVerification(verifier1);
        applyForVerification(verifier2);
        applyForVerification(verifier3);

        triggerVerification(verifier1);
        triggerVerification(verifier2);
        triggerVerification(verifier3);

        RequestDetails memory request = getRequestDetails(0);
        bytes32 computedHash1 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce1")), verifier1));
        bytes32 computedHash2 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce2")), verifier2));
        bytes32 computedHash3 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce3")), verifier3));

        submitCommitment(verifier1, computedHash1);
        submitCommitment(verifier2, computedHash2);
        submitCommitment(verifier3, computedHash3);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        revealProviderKeyAndHash(uint256(keccak256(abi.encodePacked(privateKey, bytes32(block.timestamp)))), answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        vm.startPrank(verifier1);
        market.revealCommitment(0, false, keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce1")));
        vm.stopPrank();

        vm.startPrank(verifier2);
        market.revealCommitment(0, false, keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce2")));
        vm.stopPrank();

        vm.startPrank(verifier3);
        market.revealCommitment(0, false, keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce3")));
        vm.stopPrank();

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        getRewardsAndStakes(verifier1, 1);
        getRewardsAndStakes(verifier2, 1);
        getRewardsAndStakes(verifier3, 1);

        request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));
    }

    function testNoMajorityScenario() public {
        completeTestRequest();
        applyForVerification(verifier1);
        applyForVerification(verifier2);
        applyForVerification(verifier3);

        triggerVerification(verifier1);
        triggerVerification(verifier2);
        triggerVerification(verifier3);


        RequestDetails memory request = getRequestDetails(0);
        bytes32 computedHash1 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("answer1")), keccak256(abi.encodePacked("nonce1")), verifier1));
        bytes32 computedHash2 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("answer2")), keccak256(abi.encodePacked("nonce2")), verifier2));
        bytes32 computedHash3 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("answer3")), keccak256(abi.encodePacked("nonce3")), verifier3));

        submitCommitment(verifier1, computedHash1);
        submitCommitment(verifier2, computedHash2);
        submitCommitment(verifier3, computedHash3);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("answer1"));
        revealProviderKeyAndHash(uint256(keccak256(abi.encodePacked(privateKey, bytes32(block.timestamp)))), answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        vm.startPrank(verifier1);
        market.revealCommitment(0, true, keccak256(abi.encodePacked("answer1")), keccak256(abi.encodePacked("nonce1")));
        vm.stopPrank();

        vm.startPrank(verifier2);
        market.revealCommitment(0, false, keccak256(abi.encodePacked("answer2")), keccak256(abi.encodePacked("nonce2")));
        vm.stopPrank();

        vm.startPrank(verifier3);
        market.revealCommitment(0, true, keccak256(abi.encodePacked("answer3")), keccak256(abi.encodePacked("nonce3")));
        vm.stopPrank();

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        getRewardsAndStakes(verifier1, 1);
        getRewardsAndStakes(verifier2, 1);
        getRewardsAndStakes(verifier3, 1);

        request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
    }

    function testHandleVerifierTimeout() public {
        completeTestRequest();
        applyForVerification(verifier1);
        applyForVerification(verifier2);
        applyForVerification(verifier3);

        triggerVerification(verifier1);
        triggerVerification(verifier2);
        triggerVerification(verifier3);

        RequestDetails memory request = getRequestDetails(0);
        bytes32 computedHash1 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce1")), verifier1));
        bytes32 computedHash2 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce2")), verifier2));

        submitCommitment(verifier1, computedHash1);
        submitCommitment(verifier2, computedHash2);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        revealProviderKeyAndHash(uint256(keccak256(abi.encodePacked(privateKey, bytes32(block.timestamp)))), answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        vm.startPrank(verifier1);
        market.revealCommitment(0, true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce1")));
        vm.stopPrank();

        vm.startPrank(verifier2);
        market.revealCommitment(0, true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce2")));
        vm.stopPrank();

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        getRewardsAndStakes(verifier1, 1);
        getRewardsAndStakes(verifier2, 1);
        getRewardsAndStakes(verifier3, 1);

        request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
    }

    function testProviderTimeout() public {
        completeTestRequest();
        applyForVerification(verifier1);
        applyForVerification(verifier2);
        applyForVerification(verifier3);

        triggerVerification(verifier1);
        triggerVerification(verifier2);
        triggerVerification(verifier3);

        RequestDetails memory request = getRequestDetails(0);
        bytes32 computedHash1 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce1")), verifier1));
        bytes32 computedHash2 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce2")), verifier2));
        bytes32 computedHash3 = keccak256(abi.encodePacked(keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce3")), verifier3));

        submitCommitment(verifier1, computedHash1);
        submitCommitment(verifier2, computedHash2);
        submitCommitment(verifier3, computedHash3);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        // Simulate provider timeout by not calling revealProviderKeyAndHash

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        vm.startPrank(verifier1);
        market.revealCommitment(0, true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce1")));
        vm.stopPrank();

        vm.startPrank(verifier2);
        market.revealCommitment(0, true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce2")));
        vm.stopPrank();

        vm.startPrank(verifier3);
        market.revealCommitment(0, false, keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce3")));
        vm.stopPrank();

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        getRewardsAndStakes(verifier1, 1);
        getRewardsAndStakes(verifier2, 1);
        getRewardsAndStakes(verifier3, 1);

        request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));
    }

    function testWithdrawFunds() public {
        uint256 initialConsumerBalance = compToken.balanceOf(consumer);
        uint256 initialMarketBalance = compToken.balanceOf(address(market));
        createTestRequest();

        vm.startPrank(consumer);
        market.cancelRequest(0);
        vm.stopPrank();

        RequestDetails memory request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CANCELLED));
        assertEq(compToken.balanceOf(consumer), initialConsumerBalance);
        assertEq(compToken.balanceOf(address(market)), initialMarketBalance);
    }
}
