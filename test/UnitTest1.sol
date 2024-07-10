// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
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

    address consumer = address(1);
    address provider = address(2);
    address verifier1 = address(3);
    address verifier2 = address(4);
    address verifier3 = address(5);

    uint256 paymentForProvider = 1000 * 10 ** 18;
    uint256 paymentPerRoundForVerifiers = 500 * 10 ** 18;
    uint256 totalPaymentForVerifiers;
    uint256 numOperations = 3000;
    uint256 numVerifiers = 3;
    uint256 computationDeadline = 1 days;
    uint256 verificationDeadline = 2 days;
    uint256 timeAllocatedForVerification = 1 hours;
    uint256 numVerifiersSampleSize = 3; // For testing purposes
    uint256 constant PROVIDER_STAKE_PERCENTAGE = 10;

    function setUp() public {
        // Deploy the mock COMP token and the market contract
        compToken = new MockERC20();
        market = new ComputationMarket(address(compToken));

        // Distribute COMP tokens to test accounts
        distributeTokens();

        // Label accounts for better readability in logs
        labelAccounts();

        // Calculate total payment for verifiers
        uint256 layerCount = (numOperations + 999) / 1000;
        totalPaymentForVerifiers = paymentPerRoundForVerifiers * numVerifiersSampleSize * layerCount;
    }

    function distributeTokens() internal {
        compToken.transfer(consumer, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(provider, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(verifier1, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(verifier2, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(verifier3, 1000000000000000000000000 * 10 ** compToken.decimals());
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
            numVerifiersSampleSize
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
        vm.stopPrank();
    }

    function applyForVerification(address verifierAddress) internal {
        approveTokens(verifierAddress, paymentPerRoundForVerifiers);
        vm.startPrank(verifierAddress);
        market.applyForVerificationForRequest(0);
        vm.stopPrank();
    }

    function submitCommitment(address verifierAddress, bytes32 computedHash) internal {
        vm.startPrank(verifierAddress);
        market.submitCommitment(0, computedHash);
        vm.stopPrank();
    }

    function revealProviderKeyAndHash(bytes32 privateKey, bytes32 answerHash) internal {
        vm.startPrank(provider);
        market.revealProviderKeyAndHash(0, privateKey, answerHash);
        vm.stopPrank();
    }

    function performSuccessfulRound(address v1, address v2, address v3) internal {
        applyForVerification(v1);
        applyForVerification(v2);
        applyForVerification(v3);

        bytes32 computedHash1 = keccak256(abi.encode(true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce1")), v1));
        bytes32 computedHash2 = keccak256(abi.encode(true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce2")), v2));
        bytes32 computedHash3 = keccak256(abi.encode(false, keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce3")), v3));

        submitCommitment(v1, computedHash1);
        submitCommitment(v2, computedHash2);
        submitCommitment(v3, computedHash3);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        revealProviderKeyAndHash(privateKey, answerHash);

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
        market.calculateMajorityAndReward(0);
        vm.stopPrank();
    }

    function testMajorityAgreement() public {
        completeTestRequest();
        ComputationMarket.Request memory request = market.getRequestDetails(0);
        performSuccessfulRound(verifier1, verifier2, verifier3);
        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
        performSuccessfulRound(verifier1, verifier2, verifier3);
        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
        performSuccessfulRound(verifier1, verifier2, verifier3);
        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));
    }

    function testProviderFailureWithNoMajority() public {
        completeTestRequest();
        applyForVerification(verifier1);
        applyForVerification(verifier2);
        applyForVerification(verifier3);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        bytes32 computedHash1 = keccak256(abi.encode(false, keccak256(abi.encodePacked("wrong_answer1")), keccak256(abi.encodePacked("nonce1")), verifier1));
        bytes32 computedHash2 = keccak256(abi.encode(false, keccak256(abi.encodePacked("wrong_answer2")), keccak256(abi.encodePacked("nonce2")), verifier2));
        bytes32 computedHash3 = keccak256(abi.encode(false, keccak256(abi.encodePacked("wrong_answer3")), keccak256(abi.encodePacked("nonce3")), verifier3));

        submitCommitment(verifier1, computedHash1);
        submitCommitment(verifier2, computedHash2);
        submitCommitment(verifier3, computedHash3);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        revealProviderKeyAndHash(privateKey, answerHash);

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
        market.calculateMajorityAndReward(0);

        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
        assertFalse(request.completed);
    }

    function testVerifierMajorityFailure() public {
        completeTestRequest();
        applyForVerification(verifier1);
        applyForVerification(verifier2);
        applyForVerification(verifier3);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        bytes32 computedHash1 = keccak256(abi.encode(false, keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce1")), verifier1));
        bytes32 computedHash2 = keccak256(abi.encode(false, keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce2")), verifier2));
        bytes32 computedHash3 = keccak256(abi.encode(false, keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce3")), verifier3));

        submitCommitment(verifier1, computedHash1);
        submitCommitment(verifier2, computedHash2);
        submitCommitment(verifier3, computedHash3);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        revealProviderKeyAndHash(privateKey, answerHash);

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
        market.calculateMajorityAndReward(0);

        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));
    }

    function testNoMajorityScenario() public {
        completeTestRequest();
        applyForVerification(verifier1);
        applyForVerification(verifier2);
        applyForVerification(verifier3);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        bytes32 computedHash1 = keccak256(abi.encode(true, keccak256(abi.encodePacked("answer1")), keccak256(abi.encodePacked("nonce1")), verifier1));
        bytes32 computedHash2 = keccak256(abi.encode(false, keccak256(abi.encodePacked("answer2")), keccak256(abi.encodePacked("nonce2")), verifier2));
        bytes32 computedHash3 = keccak256(abi.encode(true, keccak256(abi.encodePacked("answer3")), keccak256(abi.encodePacked("nonce3")), verifier3));

        submitCommitment(verifier1, computedHash1);
        submitCommitment(verifier2, computedHash2);
        submitCommitment(verifier3, computedHash3);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("answer1"));
        revealProviderKeyAndHash(privateKey, answerHash);

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
        market.calculateMajorityAndReward(0);

        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
    }

    function testHandleVerifierTimeout() public {
        completeTestRequest();
        applyForVerification(verifier1);
        applyForVerification(verifier2);
        applyForVerification(verifier3);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        bytes32 computedHash1 = keccak256(abi.encode(true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce1")), verifier1));
        bytes32 computedHash2 = keccak256(abi.encode(true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce2")), verifier2));

        submitCommitment(verifier1, computedHash1);
        submitCommitment(verifier2, computedHash2);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        revealProviderKeyAndHash(privateKey, answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        vm.startPrank(verifier1);
        market.revealCommitment(0, true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce1")));
        vm.stopPrank();

        vm.startPrank(verifier2);
        market.revealCommitment(0, true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce2")));
        vm.stopPrank();

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);
        market.calculateMajorityAndReward(0);

        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
    }

    function testProviderTimeout() public {
        completeTestRequest();
        applyForVerification(verifier1);
        applyForVerification(verifier2);
        applyForVerification(verifier3);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        bytes32 computedHash1 = keccak256(abi.encode(true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce1")), verifier1));
        bytes32 computedHash2 = keccak256(abi.encode(true, keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce2")), verifier2));
        bytes32 computedHash3 = keccak256(abi.encode(false, keccak256(abi.encodePacked("wrong_answer")), keccak256(abi.encodePacked("nonce3")), verifier3));

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
        market.calculateMajorityAndReward(0);

        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));
    }

    function testWithdrawFunds() public {
        uint256 initialConsumerBalance = compToken.balanceOf(consumer);
        uint256 initialMarketBalance = compToken.balanceOf(address(market));
        createTestRequest();

        vm.startPrank(consumer);
        market.cancelRequest(0);
        vm.stopPrank();

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CANCELLED));
        assertEq(compToken.balanceOf(consumer), initialConsumerBalance);
        assertEq(compToken.balanceOf(address(market)), initialMarketBalance);
    }
}
