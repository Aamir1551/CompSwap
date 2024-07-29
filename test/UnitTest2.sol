// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/ComputationMarket.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

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

    uint256 paymentForProvider = 1000 * 10 ** 18;
    uint256 paymentPerRoundForVerifiers = 500 * 10 ** 18;
    uint256 totalPaymentForVerifiers;
    uint256 numOperations = 3000;
    uint256 numVerifiers = 5;
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
        compToken.transfer(verifier4, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(verifier5, 1000000000000000000000000 * 10 ** compToken.decimals());
    }

    function labelAccounts() internal {
        vm.label(consumer, "Consumer");
        vm.label(provider, "Provider");
        vm.label(verifier1, "Verifier1");
        vm.label(verifier2, "Verifier2");
        vm.label(verifier3, "Verifier3");
        vm.label(verifier4, "Verifier4");
        vm.label(verifier5, "Verifier5");
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
            1
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

    function performRoundWithVerifiers(address[] memory verifiers, bytes32[] memory answers, bool[] memory agreements, bool majorityExpected) internal {
        // Apply for verification
        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        // Fetch the chosen verifiers from the request structure
        ComputationMarket.Request memory request = market.getRequestDetails(0);
        address[] memory chosenVerifiers = request.chosenVerifiers;

        // Submit commitment for the chosen verifiers
        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encode(answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), chosenVerifiers[i]));
            submitCommitment(chosenVerifiers[i], computedHash);
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        // Provider reveals the key and hash
        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = answers[0];
        revealProviderKeyAndHash(privateKey, answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        // Reveal commitment for the chosen verifiers
        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            vm.startPrank(chosenVerifiers[i]);
            market.revealCommitment(0, agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)));
            vm.stopPrank();
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);
        market.calculateMajorityAndReward(0);
        vm.stopPrank();

        ComputationMarket.Request memory requestUpdated = market.getRequestDetails(0);
        if (majorityExpected) {
            if(requestUpdated.layerComputeIndex == requestUpdated.layerCount) {
                assertEq(uint256(requestUpdated.state), uint256(ComputationMarket.RequestStates.SUCCESS));
            } else {
                assertEq(uint256(requestUpdated.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
            }
        } else {
            assertEq(uint256(requestUpdated.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));
        }
    }

    // Helper function to find the index of a verifier in the original list
    function findVerifierIndex(address verifier, address[] memory verifiers) internal pure returns (uint256) {
        for (uint256 i = 0; i < verifiers.length; i++) {
            if (verifiers[i] == verifier) {
                return i;
            }
        }
        revert("Verifier not found in the list");
    }

    function testMultipleRoundsWithVerifierSampling() public {
        completeTestRequest();

        address[] memory verifiers = new address[](5);
        bytes32[] memory answers = new bytes32[](5);
        bool[] memory agreements = new bool[](5);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        // Round 2
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        // Round 3
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));
    }

    function testVerifierBalancesAfterRounds() public {
        completeTestRequest();

        address[] memory verifiers = new address[](5);
        bytes32[] memory answers = new bytes32[](5);
        bool[] memory agreements = new bool[](5);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;

        // Initial balances
        uint256 initialBalanceVerifier1 = compToken.balanceOf(verifier1);
        uint256 initialBalanceVerifier2 = compToken.balanceOf(verifier2);
        uint256 initialBalanceVerifier3 = compToken.balanceOf(verifier3);
        uint256 initialBalanceVerifier4 = compToken.balanceOf(verifier4);
        uint256 initialBalanceVerifier5 = compToken.balanceOf(verifier5);

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        // Fetch the chosen verifiers from the request structure
        ComputationMarket.Request memory request = market.getRequestDetails(0);
        address[] memory chosenVerifiers = request.chosenVerifiers;

        // Balances after round 1
        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            if (agreements[verifierIndex]) {
                assertGt(compToken.balanceOf(chosenVerifiers[i]), initialBalanceVerifier1);
            } else {
                assertEq(compToken.balanceOf(chosenVerifiers[i]), initialBalanceVerifier3);
            }
        }

        // Round 2
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        // Round 3
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        performRoundWithVerifiers(verifiers, answers, agreements, true);

        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));
    }


    function testCancelRequestAfterSelection() public {
        createTestRequest();

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

    function testVerifierTimeoutWithPartialReveals() public {
        completeTestRequest();

        address[] memory verifiers = new address[](5);
        bytes32[] memory answers = new bytes32[](5);
        bool[] memory agreements = new bool[](5);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;

        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        address[] memory chosenVerifiers = request.chosenVerifiers;

        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encode(answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), chosenVerifiers[i]));
            submitCommitment(chosenVerifiers[i], computedHash);
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = answers[0];
        revealProviderKeyAndHash(privateKey, answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        // Only partial reveals
        for (uint256 i = 0; i < chosenVerifiers.length - 1; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            vm.startPrank(chosenVerifiers[i]);
            market.revealCommitment(0, agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)));
            vm.stopPrank();
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);
        market.calculateMajorityAndReward(0);

        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
        }

    function testProviderTimeoutScenario() public {
        completeTestRequest();

        address[] memory verifiers = new address[](5);
        bytes32[] memory answers = new bytes32[](5);
        bool[] memory agreements = new bool[](5);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;

        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        address[] memory chosenVerifiers = request.chosenVerifiers;

        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encode(answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), chosenVerifiers[i]));
            submitCommitment(chosenVerifiers[i], computedHash);
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        // Simulate provider timeout by not calling revealProviderKeyAndHash

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            vm.startPrank(chosenVerifiers[i]);
            market.revealCommitment(0, agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)));
            vm.stopPrank();
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);
        market.calculateMajorityAndReward(0);

        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));
    }
}
