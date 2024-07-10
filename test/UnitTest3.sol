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
    address verifier4 = address(6);
    address verifier5 = address(7);
    address verifier6 = address(8);
    address verifier7 = address(9);

    uint256 paymentForProvider = 1000 * 10 ** 18;
    uint256 paymentPerRoundForVerifiers = 500 * 10 ** 18;
    uint256 totalPaymentForVerifiers;
    uint256 numOperations = 3000;
    uint256 numVerifiers = 7;
    uint256 computationDeadline = 1 days;
    uint256 verificationDeadline = 2 days;
    uint256 timeAllocatedForVerification = 1 hours;
    uint256 numVerifiersSampleSize = 5; // For testing purposes
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
        compToken.transfer(verifier4, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(verifier5, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(verifier6, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(verifier7, 1000000000000000000000000 * 10 ** compToken.decimals());
    }

    function labelAccounts() internal {
        vm.label(consumer, "Consumer");
        vm.label(provider, "Provider");
        vm.label(verifier1, "Verifier1");
        vm.label(verifier2, "Verifier2");
        vm.label(verifier3, "Verifier3");
        vm.label(verifier4, "Verifier4");
        vm.label(verifier5, "Verifier5");
        vm.label(verifier6, "Verifier6");
        vm.label(verifier7, "Verifier7");
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

    function findVerifierIndex(address verifier, address[] memory verifiers) internal pure returns (uint256) {
        for (uint256 i = 0; i < verifiers.length; i++) {
            if (verifiers[i] == verifier) {
                return i;
            }
        }
        revert("Verifier not found");
    }

    function performRoundWithVerifiers(address[] memory verifiers, bytes32[] memory answers, bool[] memory agreements, bool majorityExpected) internal {
        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        ComputationMarket.Request memory request = market.getRequestDetails(0);

        for (uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(request.chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encode(agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), request.chosenVerifiers[i]));
            submitCommitment(request.chosenVerifiers[i], computedHash);
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = answers[0];
        revealProviderKeyAndHash(privateKey, answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        for (uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(request.chosenVerifiers[i], verifiers);
            vm.startPrank(request.chosenVerifiers[i]);
            market.revealCommitment(0, agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)));
            vm.stopPrank();
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);
        market.calculateMajorityAndReward(0);
        vm.stopPrank();

        request = market.getRequestDetails(0);
        if (majorityExpected) {
            assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
        } else {
            assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));
        }
    }

    function testVerifierBalancesAfterRounds() public {
        completeTestRequest();

        address[] memory verifiers = new address[](7);
        bytes32[] memory answers = new bytes32[](7);
        bool[] memory agreements = new bool[](7);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;
        verifiers[5] = verifier6;
        verifiers[6] = verifier7;

        // Initial balances
        uint256 initialBalanceVerifier1 = compToken.balanceOf(verifier1);
        uint256 initialBalanceVerifier2 = compToken.balanceOf(verifier2);
        uint256 initialBalanceVerifier3 = compToken.balanceOf(verifier3);
        uint256 initialBalanceVerifier4 = compToken.balanceOf(verifier4);
        uint256 initialBalanceVerifier5 = compToken.balanceOf(verifier5);
        uint256 initialBalanceVerifier6 = compToken.balanceOf(verifier6);
        uint256 initialBalanceVerifier7 = compToken.balanceOf(verifier7);

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        // Balances after round 1
        uint256 newBalanceVerifier1 = compToken.balanceOf(verifier1);
        uint256 newBalanceVerifier2 = compToken.balanceOf(verifier2);
        uint256 newBalanceVerifier3 = compToken.balanceOf(verifier3);
        uint256 newBalanceVerifier4 = compToken.balanceOf(verifier4);
        uint256 newBalanceVerifier5 = compToken.balanceOf(verifier5);
        uint256 newBalanceVerifier6 = compToken.balanceOf(verifier6);
        uint256 newBalanceVerifier7 = compToken.balanceOf(verifier7);
        assertEq(newBalanceVerifier1, initialBalanceVerifier1 + paymentPerRoundForVerifiers);
        assertEq(newBalanceVerifier2, initialBalanceVerifier2 + paymentPerRoundForVerifiers);
        assertEq(newBalanceVerifier3, initialBalanceVerifier3); // verifier3 didn't agree, so no reward
        assertEq(newBalanceVerifier4, initialBalanceVerifier4 + paymentPerRoundForVerifiers);
        assertEq(newBalanceVerifier5, initialBalanceVerifier5 + paymentPerRoundForVerifiers);
        assertEq(newBalanceVerifier6, initialBalanceVerifier6 + paymentPerRoundForVerifiers);
        assertEq(newBalanceVerifier7, initialBalanceVerifier7 + paymentPerRoundForVerifiers);

        // Round 2
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        // Round 3
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));
    }

    function testCancelRequestAfterSelection() public {
        createTestRequest();

        vm.startPrank(provider);
        uint256 stakeAmount = (paymentForProvider * PROVIDER_STAKE_PERCENTAGE) / 100;
        compToken.approve(address(market), stakeAmount);
        market.selectRequest(0);
        vm.stopPrank();

        vm.warp(block.timestamp + computationDeadline + 1); // Ensure computation deadline has passed

        vm.startPrank(consumer);
        market.cancelRequest(0);
        vm.stopPrank();

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        assertTrue(request.completed);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CANCELLED));
    }

    function testErrorsAndRequiredStatements() public {
        createTestRequest();
        vm.startPrank(provider);
        vm.expectRevert("Insufficient stake");
        market.selectRequest(0);
        vm.stopPrank();
    }

    function testMultipleRoundsWithVerifierSampling() public {
        completeTestRequest();

        address[] memory verifiers = new address[](7);
        bytes32[] memory answers = new bytes32[](7);
        bool[] memory agreements = new bool[](7);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;
        verifiers[5] = verifier6;
        verifiers[6] = verifier7;

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        // Round 2
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        // Round 3
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));
    }

    function testVerifierTimeoutWithPartialReveals() public {
        completeTestRequest();

        address[] memory verifiers = new address[](7);
        bytes32[] memory answers = new bytes32[](7);
        bool[] memory agreements = new bool[](7);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;
        verifiers[5] = verifier6;
        verifiers[6] = verifier7;

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;

        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        ComputationMarket.Request memory request = market.getRequestDetails(0);

        for (uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(request.chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encode(agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), request.chosenVerifiers[i]));
            submitCommitment(request.chosenVerifiers[i], computedHash);
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = answers[0];
        revealProviderKeyAndHash(privateKey, answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        // Only partial reveals
        vm.startPrank(request.chosenVerifiers[0]);
        uint256 verifierIndex0 = findVerifierIndex(request.chosenVerifiers[0], verifiers);
        market.revealCommitment(0, agreements[verifierIndex0], answers[verifierIndex0], keccak256(abi.encodePacked("nonce", verifierIndex0)));
        vm.stopPrank();

        vm.startPrank(request.chosenVerifiers[1]);
        uint256 verifierIndex1 = findVerifierIndex(request.chosenVerifiers[1], verifiers);
        market.revealCommitment(0, agreements[verifierIndex1], answers[verifierIndex1], keccak256(abi.encodePacked("nonce", verifierIndex1)));
        vm.stopPrank();

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);
        market.calculateMajorityAndReward(0);

        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
    }

    function testProviderTimeoutScenario() public {
        completeTestRequest();

        address[] memory verifiers = new address[](7);
        bytes32[] memory answers = new bytes32[](7);
        bool[] memory agreements = new bool[](7);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;
        verifiers[5] = verifier6;
        verifiers[6] = verifier7;

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;

        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        ComputationMarket.Request memory request = market.getRequestDetails(0);

        for (uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(request.chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encode(agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), request.chosenVerifiers[i]));
            submitCommitment(request.chosenVerifiers[i], computedHash);
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        // Simulate provider timeout by not calling revealProviderKeyAndHash

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        for (uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(request.chosenVerifiers[i], verifiers);
            vm.startPrank(request.chosenVerifiers[i]);
            market.revealCommitment(0, agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)));
            vm.stopPrank();
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);
        market.calculateMajorityAndReward(0);

        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));
    }
}
