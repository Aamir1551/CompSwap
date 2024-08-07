// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/ComputationMarket.sol";
import "../contracts/COMPToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ComputationMarketTest is Test {
    ComputationMarket public market;
    COMPToken public compToken;
    //CompNFT public compNFT;

    address consumer = address(1);
    address provider = address(2);
    address verifier1 = address(3);
    address verifier2 = address(4);
    address verifier3 = address(5);
    address verifier4 = address(6);
    address verifier5 = address(7);
    address verifier6 = address(8);
    address verifier7 = address(9);

    uint256 paymentForProvider = 100;
    uint256 paymentPerRoundForVerifiers = 10;
    uint256 totalPaymentForVerifiers;
    uint256 numOperations = 3000;
    uint256 numVerifiers = 7;
    uint256 computationDeadline = 1 days;
    uint256 verificationDeadline = 2 days;
    uint256 timeAllocatedForVerification = 1 hours;
    uint256 numVerifiersSampleSize = 5;
    uint256 constant PROVIDER_STAKE_PERCENTAGE = 25;

    function setUp() public {
        // Deploy the mock COMP token and the market contract
        compToken = new COMPToken(100000);
        //compNFT = new CompNFT();
        market = new ComputationMarket(address(compToken));
        //compNFT.transferNFTContractOwnership(address(market));

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
        compToken.transfer(provider, paymentForProvider * PROVIDER_STAKE_PERCENTAGE / 100);
        compToken.transfer(verifier1, paymentPerRoundForVerifiers);
        compToken.transfer(verifier2, paymentPerRoundForVerifiers);
        compToken.transfer(verifier3, paymentPerRoundForVerifiers);
        compToken.transfer(verifier4, paymentPerRoundForVerifiers);
        compToken.transfer(verifier5, paymentPerRoundForVerifiers);
        compToken.transfer(verifier6, paymentPerRoundForVerifiers);
        compToken.transfer(verifier7, paymentPerRoundForVerifiers);
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
        string[] memory outputFileURLs = new string[](1);
        outputFileURLs[0] = "output_file_url";

        vm.startPrank(provider);
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

    function revealProviderKeyAndHash(bytes32 privateKey, bytes32 answerHash) internal {
        vm.startPrank(provider);
        uint256 initialisationVector = block.timestamp;
        market.revealProviderKeyAndHash(0, uint256(keccak256(abi.encodePacked(privateKey, bytes32(block.timestamp)))), initialisationVector, answerHash);
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

    function collectRewards(address verifierAddress, uint256 requestId, uint256 roundNum) internal {
        vm.startPrank(verifierAddress);
        market.calculateMajorityAndReward(requestId, roundNum);
        vm.stopPrank();
    }

    function allVerifiersCollectRewards(uint256 requestId, uint256 roundNum) internal {
        ComputationMarket.Request memory request = market.getRequestDetails(requestId);
        for(uint256 i = 0; i < request.numVerifiersSampleSize; i++) {
            collectRewards(request.chosenVerifiers[i], requestId, roundNum);
        }
    }

    // Helper functions also returns the chosen verifiers
    function performRoundWithVerifiers(address[] memory verifiers, bytes32[] memory answers, bool[] memory agreements, bool majorityExpected, uint256 roundNum) internal returns(address[] memory chosenVerifiers) {
        
        // Apply for verification
        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        // Trigger verification
        for (uint256 i = 0; i < verifiers.length; i++) {
            triggerVerification(verifiers[i]);
        }

        // Fetch the chosen verifiers from the request structure
        ComputationMarket.Request memory request = market.getRequestDetails(0);
        correctNumberOfVerifiersChosen(request);
        chosenVerifiers = request.chosenVerifiers;

        for (uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(request.chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encodePacked(answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), request.chosenVerifiers[i]));
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

        allVerifiersCollectRewards(0, roundNum);
        vm.stopPrank();

        request = market.getRequestDetails(0);
        if (majorityExpected) {
            if(request.layerComputeIndex == request.layerCount) {
                assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));
            } else {
                assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
            }
        } else {
            assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));
        }
        return chosenVerifiers;
    }

    function checkBalancesAfterRound(uint256[] memory verifierBalancesBeforeRound,uint256 roundNum, address[] memory chosenVerifiersFromRound, bytes32[] memory answers, bool[] memory agreements, address[] memory verifiers) public view {
        // We check the chosen verifiers list in the request structure and make sure only the ones that were chosen were rewarded
        ComputationMarket.Request memory request = market.getRequestDetails(0);
        ComputationMarket.RoundDetailsOutput memory round = market.getRoundDetails(0, roundNum);
        // Get number of verifiers who agreed with the majority
        uint256 majorityCountOfVerifiersInRound = round.majorityCount;
        uint256 amountPaidForCorrectAnswer = request.paymentPerRoundForVerifiers * request.numVerifiersSampleSize / majorityCountOfVerifiersInRound;

        for(uint256 i = 0; i < chosenVerifiersFromRound.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiersFromRound[i], verifiers);
            // Ensure that verifier has been either been rewarded or has now lost their stake if they disagreed with the majority

            bytes32 computedHashForVerifier = keccak256(abi.encodePacked(answers[verifierIndex], agreements[verifierIndex]));

            uint256 newBalanceOfVerifier = compToken.balanceOf(chosenVerifiersFromRound[i]);
            if(computedHashForVerifier == market.getRoundDetails(0, roundNum).majorityVoteHash) {
                assertEq(newBalanceOfVerifier, verifierBalancesBeforeRound[verifierIndex] + amountPaidForCorrectAnswer);
                verifierBalancesBeforeRound[verifierIndex] = newBalanceOfVerifier;
            } else {
                assertEq(newBalanceOfVerifier, verifierBalancesBeforeRound[verifierIndex] - paymentPerRoundForVerifiers);
                verifierBalancesBeforeRound[verifierIndex] = newBalanceOfVerifier;
            }
        }
    }

    // Ensure that only 5 verifiers from the 7 verifiers are chosen for verification
    function correctNumberOfVerifiersChosen(ComputationMarket.Request memory request) public view {
        address[] memory isVerifierChosen = new address[](7);
        assertEq(request.chosenVerifiers.length, 5);
        for(uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            // Check if the chosen verifier has been chosen
            for(uint256 j = 0; j < i; j++) {
                assertNotEq(request.chosenVerifiers[i], isVerifierChosen[j]);
            }
            isVerifierChosen[i] = request.chosenVerifiers[i];
        }
    }

    function testVerifierBalancesAfterRounds() public {
        
        // Initial balances of Consumer and Provider
        uint256 consumerBalanceBefore = compToken.balanceOf(consumer);
        uint256 providerBalanceBefore = compToken.balanceOf(provider);

        completeTestRequest();

        address[] memory verifiers = new address[](7);
        bytes32[] memory answers = new bytes32[](7);
        bool[] memory agreements = new bool[](7);
        uint256[] memory verifierBalances = new uint256[](7);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;
        verifiers[5] = verifier6;
        verifiers[6] = verifier7;

        for(uint256 i=0; i<verifiers.length; i++) {
            verifierBalances[i] = compToken.balanceOf(verifiers[i]);
        }

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer123"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;
        address[] memory chosenVerifiersFromRound = performRoundWithVerifiers(verifiers, answers, agreements, true, 1);
        checkBalancesAfterRound(verifierBalances, 1, chosenVerifiersFromRound, answers, agreements, verifiers);

        for(uint256 i=0; i<verifiers.length; i++) {
            if(compToken.balanceOf(verifiers[i]) == 0) {
                compToken.transfer(verifiers[i], 10);
                verifierBalances[i] = compToken.balanceOf(verifiers[i]);
            }
        }

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
        chosenVerifiersFromRound = performRoundWithVerifiers(verifiers, answers, agreements, true, 2);
        checkBalancesAfterRound(verifierBalances, 2, chosenVerifiersFromRound, answers, agreements, verifiers);

        for(uint256 i=0; i<verifiers.length; i++) {
            if(compToken.balanceOf(verifiers[i]) == 0) {
                compToken.transfer(verifiers[i], 10);
                verifierBalances[i] = compToken.balanceOf(verifiers[i]);
            }
        }

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
        chosenVerifiersFromRound = performRoundWithVerifiers(verifiers, answers, agreements, true, 3);
        checkBalancesAfterRound(verifierBalances, 3, chosenVerifiersFromRound, answers, agreements, verifiers);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));

        // Check balance of consumer
        assertEq(compToken.balanceOf(consumer), consumerBalanceBefore - paymentForProvider - paymentPerRoundForVerifiers * 3 * 5);

        // Check balance of provider
        assertEq(compToken.balanceOf(provider), providerBalanceBefore + paymentForProvider);
    }

    function testCancelRequestAfterSelection() public {
        // Initial balance of consumer
        uint256 initialBalanceConsumer = compToken.balanceOf(consumer);

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

        // Check balance of consumer after request is cancelled
        assertEq(compToken.balanceOf(consumer), initialBalanceConsumer + stakeAmount);
    }

    function testErrorsAndRequiredStatements() public {
        createTestRequest();
        vm.startPrank(provider);
        vm.expectRevert("Insufficient stake");
        market.selectRequest(0);
        vm.stopPrank();
    }

    function testWhenProviderIsIncorrect() public {
        
        // Initial balances of Consumer and Provider
        uint256 consumerBalanceBefore = compToken.balanceOf(consumer);
        uint256 providerBalanceBefore = compToken.balanceOf(provider);

        completeTestRequest();

        address[] memory verifiers = new address[](7);
        bytes32[] memory answers = new bytes32[](7);
        bool[] memory agreements = new bool[](7);
        uint256[] memory verifierBalances = new uint256[](7);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;
        verifiers[5] = verifier6;
        verifiers[6] = verifier7;

        for(uint256 i=0; i<verifiers.length; i++) {
            verifierBalances[i] = compToken.balanceOf(verifiers[i]);
        }

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer123"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;
        address[] memory chosenVerifiersFromRound = performRoundWithVerifiers(verifiers, answers, agreements, true, 1);
        checkBalancesAfterRound(verifierBalances, 1, chosenVerifiersFromRound, answers, agreements, verifiers);

        for(uint256 i=0; i<verifiers.length; i++) {
            if(compToken.balanceOf(verifiers[i]) == 0) {
                compToken.transfer(verifiers[i], 10);
                verifierBalances[i] = compToken.balanceOf(verifiers[i]);
            }
        }

        // Round 2
        answers[0] = keccak256(abi.encodePacked("answer4"));
        answers[1] = keccak256(abi.encodePacked("answer4"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer4"));
        answers[4] = keccak256(abi.encodePacked("answer4"));
        answers[5] = keccak256(abi.encodePacked("answer4"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = false;
        agreements[1] = false;
        agreements[2] = false;
        agreements[3] = false;
        agreements[4] = false;
        agreements[5] = false;
        agreements[6] = false;
        chosenVerifiersFromRound = performRoundWithVerifiers(verifiers, answers, agreements, false, 2);
        checkBalancesAfterRound(verifierBalances, 2, chosenVerifiersFromRound, answers, agreements, verifiers);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));

        uint256 stakeAmount = (paymentForProvider * PROVIDER_STAKE_PERCENTAGE) / 100;
        // Check balance of consumer
        assertEq(compToken.balanceOf(consumer), consumerBalanceBefore + stakeAmount - paymentPerRoundForVerifiers * 2 * 5);

        // Check balance of provider
        assertEq(compToken.balanceOf(provider), providerBalanceBefore - stakeAmount);
    }

    function testVerifierTimeoutWithPartialReveals() public {
        // Initial balances of Consumer and Provider
        uint256 consumerBalanceBefore = compToken.balanceOf(consumer);
        uint256 providerBalanceBefore = compToken.balanceOf(provider);

        completeTestRequest();

        address[] memory verifiers = new address[](7);
        bytes32[] memory answers = new bytes32[](7);
        bool[] memory agreements = new bool[](7);
        uint256[] memory verifierBalances = new uint256[](7);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;
        verifiers[5] = verifier6;
        verifiers[6] = verifier7;

        for(uint256 i=0; i<verifiers.length; i++) {
            verifierBalances[i] = compToken.balanceOf(verifiers[i]);
        }

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer123"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;

        // Apply for verification
        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        // Trigger verification
        for (uint256 i = 0; i < verifiers.length; i++) {
            triggerVerification(verifiers[i]);
        }

        // Fetch the chosen verifiers from the request structure
        ComputationMarket.Request memory request = market.getRequestDetails(0);
        correctNumberOfVerifiersChosen(request);

        for (uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(request.chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encodePacked(answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), request.chosenVerifiers[i]));
            //submitCommitment(request.chosenVerifiers[i], computedHash);
            if(i <= 3) {
                submitCommitment(request.chosenVerifiers[i], computedHash);
            }
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = answers[0];
        revealProviderKeyAndHash(privateKey, answerHash);

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        for (uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(request.chosenVerifiers[i], verifiers);
            vm.startPrank(request.chosenVerifiers[i]);
            if(i <= 3) {
                market.revealCommitment(0, agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)));
            }
            vm.stopPrank();
        }

        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        address[] memory chosenVerifiersForRound = request.chosenVerifiers;
        allVerifiersCollectRewards(0, 1);

        // We check the chosen verifiers list in the request structure and make sure only the ones that were chosen were rewarded
        request = market.getRequestDetails(0);
        ComputationMarket.RoundDetailsOutput memory round = market.getRoundDetails(0, 1);
        // Get number of verifiers who agreed with the majority
        uint256 majorityCountOfVerifiersInRound = round.majorityCount;
        uint256 amountPaidForCorrectAnswer = request.paymentPerRoundForVerifiers * request.numVerifiersSampleSize / majorityCountOfVerifiersInRound;

        for(uint256 i = 0; i < chosenVerifiersForRound.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiersForRound[i], verifiers);
            // Ensure that verifier has been either been rewarded or has now lost their stake if they disagreed with the majority

            bytes32 computedHashForVerifier = keccak256(abi.encodePacked(answers[verifierIndex], agreements[verifierIndex]));
            if(i > 3) {
                computedHashForVerifier = bytes32(0);
            }

            uint256 newBalanceOfVerifier = compToken.balanceOf(chosenVerifiersForRound[i]);
            if(computedHashForVerifier == market.getRoundDetails(0, 1).majorityVoteHash) {
                assertEq(newBalanceOfVerifier, verifierBalances[verifierIndex] + amountPaidForCorrectAnswer);
                verifierBalances[verifierIndex] = newBalanceOfVerifier;
            } else {
                assertEq(newBalanceOfVerifier, verifierBalances[verifierIndex] - paymentPerRoundForVerifiers);
                verifierBalances[verifierIndex] = newBalanceOfVerifier;
            }
        }
        request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
    }

    // In general we do not expect verifiers to not trigger at all, since they are losing stake
    function testSomeVerifiersNotTriggered() public {
        // Initial balances of Consumer and Provider
        uint256 consumerBalanceBefore = compToken.balanceOf(consumer);
        uint256 providerBalanceBefore = compToken.balanceOf(provider);

        completeTestRequest();

        address[] memory verifiers = new address[](7);
        bytes32[] memory answers = new bytes32[](7);
        bool[] memory agreements = new bool[](7);
        uint256[] memory verifierBalances = new uint256[](7);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;
        verifiers[5] = verifier6;
        verifiers[6] = verifier7;

        for(uint256 i=0; i<verifiers.length; i++) {
            verifierBalances[i] = compToken.balanceOf(verifiers[i]);
        }

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer123"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;

        // Apply for verification
        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        // Trigger verification. Last verifier is not triggered
        for (uint256 i = 0; i < verifiers.length-1; i++) {
            triggerVerification(verifiers[i]);
        }

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        // Get Address of verifier that triggered but is not chosen and has not been paid
        address verifierNotChosenButTriggered = address(0);
        for(uint256 i=0; i<verifiers.length-1; i++) {
            if(market.getVerificationDetails(0, 1, verifiers[i]).verifierPaid) {
                continue;
            }
            bool verifierNotChosenButTriggeredFound = true;
            for(uint256 j=0; j<request.chosenVerifiers.length; j++) {
                if(verifiers[i] == request.chosenVerifiers[j]) {
                    verifierNotChosenButTriggeredFound = false;
                }
            }
            if(verifierNotChosenButTriggeredFound) {
                verifierNotChosenButTriggered = verifiers[i];
                break;
            }
        }

        // Get balance of verifier that triggered but is not chosen and the verifier that did not trigger
        uint256 balanceOfVerifierNotChosenButTriggered = compToken.balanceOf(verifierNotChosenButTriggered);
        uint256 balanceOfVerifierDidNotTrigger = compToken.balanceOf(verifiers[verifiers.length-1]);

        //console.log("start here");
        //console.log(verifierNotChosenButTriggered);
        //vm.startPrank(verifierNotChosenButTriggered);
        //market.returnStake(0, 1);
        //vm.stopPrank();
        vm.startPrank(verifiers[verifiers.length-1]);
        vm.expectRevert("You did not trigger");
        market.returnStake(0, 1);
        vm.stopPrank();

        // Check Balance for Verifier that triggered but was not chosen
        //assertEq(compToken.balanceOf(verifierNotChosenButTriggered), balanceOfVerifierNotChosenButTriggered + paymentPerRoundForVerifiers);

        // Check Balance for verifier that did not trigger
        assertEq(compToken.balanceOf(verifiers[verifiers.length-1]), balanceOfVerifierDidNotTrigger);

    }

    /*function testProviderTimeoutScenario() public {
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
            bytes32 computedHash = keccak256(abi.encodePacked(agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), request.chosenVerifiers[i]));
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
    }*/

    /*function testNewProviderHolderBalanceAfterRounds() public {
        
        // Initial balances of Consumer and Provider
        uint256 consumerBalanceBefore = compToken.balanceOf(consumer);
        uint256 providerBalanceBefore = compToken.balanceOf(provider);

        completeTestRequest();

        // Hand over the nft to a new address
        address newProvider = address(100);
        vm.startPrank(provider);
        market.compNFT().safeTransferFrom(provider, newProvider, 0);
        vm.stopPrank();

        address[] memory verifiers = new address[](7);
        bytes32[] memory answers = new bytes32[](7);
        bool[] memory agreements = new bool[](7);
        uint256[] memory verifierBalances = new uint256[](7);

        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        verifiers[3] = verifier4;
        verifiers[4] = verifier5;
        verifiers[5] = verifier6;
        verifiers[6] = verifier7;

        for(uint256 i=0; i<verifiers.length; i++) {
            verifierBalances[i] = compToken.balanceOf(verifiers[i]);
        }

        // Round 1
        answers[0] = keccak256(abi.encodePacked("answer"));
        answers[1] = keccak256(abi.encodePacked("answer"));
        answers[2] = keccak256(abi.encodePacked("wrong_answer"));
        answers[3] = keccak256(abi.encodePacked("answer"));
        answers[4] = keccak256(abi.encodePacked("answer123"));
        answers[5] = keccak256(abi.encodePacked("answer"));
        answers[6] = keccak256(abi.encodePacked("answer"));
        agreements[0] = true;
        agreements[1] = true;
        agreements[2] = false;
        agreements[3] = true;
        agreements[4] = true;
        agreements[5] = true;
        agreements[6] = true;
        address[] memory chosenVerifiersFromRound = performRoundWithVerifiers(verifiers, answers, agreements, true, 1);
        checkBalancesAfterRound(verifierBalances, 1, chosenVerifiersFromRound, answers, agreements, verifiers);

        for(uint256 i=0; i<verifiers.length; i++) {
            if(compToken.balanceOf(verifiers[i]) == 0) {
                compToken.transfer(verifiers[i], 10);
                verifierBalances[i] = compToken.balanceOf(verifiers[i]);
            }
        }

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
        chosenVerifiersFromRound = performRoundWithVerifiers(verifiers, answers, agreements, true, 2);
        checkBalancesAfterRound(verifierBalances, 2, chosenVerifiersFromRound, answers, agreements, verifiers);

        for(uint256 i=0; i<verifiers.length; i++) {
            if(compToken.balanceOf(verifiers[i]) == 0) {
                compToken.transfer(verifiers[i], 10);
                verifierBalances[i] = compToken.balanceOf(verifiers[i]);
            }
        }

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
        chosenVerifiersFromRound = performRoundWithVerifiers(verifiers, answers, agreements, true, 3);
        checkBalancesAfterRound(verifierBalances, 3, chosenVerifiersFromRound, answers, agreements, verifiers);

        ComputationMarket.Request memory request = market.getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));

        // Check balance of consumer
        assertEq(compToken.balanceOf(consumer), consumerBalanceBefore - paymentForProvider - paymentPerRoundForVerifiers * 3 * 5);

        // Check balance of provider
        assertEq(compToken.balanceOf(newProvider), paymentForProvider + request.stake);
    }*/

}