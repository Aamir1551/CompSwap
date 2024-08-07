// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/ComputationMarket.sol";
import "../contracts/COMPToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ComputationMarketTest is Test {
    ComputationMarket public market;
    COMPToken public compToken;
    CompNFT public compNFT;
    HandlerFunctionsCompMarket public handler;

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
    uint256 constant PROVIDER_STAKE_PERCENTAGE = 20;

    function setUp() public {
        // Deploy the mock COMP token and the market contract
        compToken = new COMPToken(1000000000000000000000000000 * 10 ** 18);
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
            1,
            1000,
            bytes32(0),
            paymentForProvider * PROVIDER_STAKE_PERCENTAGE / 100
        );
        vm.stopPrank();
    }

    function triggerVerification(address verifierAddress) internal {
        vm.startPrank(verifierAddress);
        market.chooseVerifiersForRequestTrigger(0);
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

    function submitCommitment(address verifierAddress, bytes32 computedHash) internal {
        vm.startPrank(verifierAddress);
        market.submitCommitment(0, computedHash);
        vm.stopPrank();
    }

    function revealProviderKeyAndHash(bytes32 privateKey, bytes32 answerHash) internal {
        vm.startPrank(provider);
        uint256 initialisationVector = block.timestamp;
        market.revealProviderKeyAndHash(0, block.timestamp, initialisationVector, answerHash);
        vm.stopPrank();
    }

    function collectRewards(address verifierAddress, uint256 requestId, uint256 roundNum) internal {
        vm.startPrank(verifierAddress);
        market.calculateMajorityAndReward(requestId, roundNum);
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


    function allVerifiersCollectRewards(address[] memory verifiers, uint256 requestId, uint256 roundNum) internal {
        for(uint256 i = 0; i < verifiers.length; i++) {
            if(market.isVerifierChosenForRound(requestId, roundNum, verifiers[i])) {
                collectRewards(verifiers[i], requestId, roundNum);
            }
        }
    }

    function performRoundWithVerifiers(address[] memory verifiers, bytes32[] memory answers, bool[] memory agreements, bool majorityExpected, uint256 roundNum) internal {
        // Apply for verification
        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        // Trigger verification
        for (uint256 i = 0; i < verifiers.length; i++) {
            triggerVerification(verifiers[i]);
        }

        // Fetch the chosen verifiers from the request structure
        RequestDetails memory request = getRequestDetails(0);
        address[] memory chosenVerifiers = getVerifiersChosen(0, roundNum, verifiers);

        // Submit commitment for the chosen verifiers
        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encodePacked(answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), chosenVerifiers[i]));
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
        allVerifiersCollectRewards(verifiers, 0, roundNum);
        vm.stopPrank();

        RequestDetails memory requestUpdated = getRequestDetails(0);
        if (majorityExpected) {
            if(requestUpdated.layerComputeIndex == requestUpdated.layerCount) {
                assertEq(uint256(requestUpdated.state), uint256(ComputationMarket.RequestStates.SUCCESS), "Incorrect state");
            } else {
                assertEq(uint256(requestUpdated.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS), "Incorrect state");
            }
        } else {
            assertEq(uint256(requestUpdated.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL), "Incorrect state");
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
        performRoundWithVerifiers(verifiers, answers, agreements, true, 1);

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
        performRoundWithVerifiers(verifiers, answers, agreements, true, 2);

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
        performRoundWithVerifiers(verifiers, answers, agreements, true, 3);

        RequestDetails memory request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));
    }

    function getVerifiersChosen(uint256 requestId, uint256 roundNum ,address[] memory verifiers) internal view returns (address[] memory) {
        address[] memory chosenVerifiers = new address[](verifiers.length);
        uint256 k = 0;

        for (uint256 i = 0; i < verifiers.length; i++) {
            if (market.isVerifierChosenForRound(requestId, roundNum, verifiers[i])) {
                chosenVerifiers[k] = verifiers[i];
                k++;
            }
        }

        // Resize the array to remove unused slots
        address[] memory result = new address[](k);
        for (uint256 i = 0; i < k; i++) {
            result[i] = chosenVerifiers[i];
        }

        return result; 
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
        performRoundWithVerifiers(verifiers, answers, agreements, true, 1);

        // Fetch the chosen verifiers from the request structure
        RequestDetails memory request = getRequestDetails(0);
        address[] memory chosenVerifiers = getVerifiersChosen(0, 1, verifiers);

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
        performRoundWithVerifiers(verifiers, answers, agreements, true, 2);

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
        performRoundWithVerifiers(verifiers, answers, agreements, true, 3);

        request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));
    }


    function testCancelRequestAfterSelection() public {
        createTestRequest();

        vm.startPrank(consumer);
        market.cancelRequest(0);
        vm.stopPrank();

        RequestDetails memory request = getRequestDetails(0);
        assertTrue(request.completed);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CANCELLED));
    }

    function testErrorsAndRequiredStatements() public {
        createTestRequest();
        vm.startPrank(provider);
        vm.expectRevert("Prov INS");
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

        for (uint256 i = 0; i < verifiers.length; i++) {
            triggerVerification(verifiers[i]);
        }
        RequestDetails memory request = getRequestDetails(0);
        address[] memory chosenVerifiers = getVerifiersChosen(0, 1, verifiers);

        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encodePacked(answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), chosenVerifiers[i]));
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
        //market.calculateMajorityAndReward(0);
        allVerifiersCollectRewards(verifiers, 0, 1);

        request = getRequestDetails(0);
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

        for (uint256 i = 0; i < verifiers.length; i++) {
            triggerVerification(verifiers[i]);
        }

        RequestDetails memory request = getRequestDetails(0);
        address[] memory chosenVerifiers = getVerifiersChosen(0, 1, verifiers);

        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encodePacked(answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), chosenVerifiers[i]));
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
        allVerifiersCollectRewards(verifiers, 0, 1);

        request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.UNSUCCESSFUL));
    }

    function testMultipleRoundsWithVerifierSamplingWithoutTimeWarps() public {
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
        performRoundWithVerifiers(verifiers, answers, agreements, true, 1);

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
        performRoundWithVerifiers(verifiers, answers, agreements, true, 2);

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
        performRoundWithVerifiersWithoutTimeWarps(verifiers, answers, agreements, true, 3);

        RequestDetails memory request = getRequestDetails(0);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.SUCCESS));
    }

    function performRoundWithVerifiersWithoutTimeWarps(address[] memory verifiers, bytes32[] memory answers, bool[] memory agreements, bool majorityExpected, uint256 roundNum) internal {
        // Apply for verification
        for (uint256 i = 0; i < verifiers.length; i++) {
            applyForVerification(verifiers[i]);
        }

        // Trigger verification
        for (uint256 i = 0; i < verifiers.length; i++) {
            triggerVerification(verifiers[i]);
        }

        // Fetch the chosen verifiers from the request structure
        RequestDetails memory request = getRequestDetails(0);
        address[] memory chosenVerifiers = getVerifiersChosen(0, roundNum, verifiers);

        // Submit commitment for the chosen verifiers
        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            bytes32 computedHash = keccak256(abi.encodePacked(answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)), chosenVerifiers[i]));
            submitCommitment(chosenVerifiers[i], computedHash);
        }

        // Provider reveals the key and hash
        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = answers[0];
        revealProviderKeyAndHash(privateKey, answerHash);

        // Reveal commitment for the chosen verifiers
        for (uint256 i = 0; i < chosenVerifiers.length; i++) {
            uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i], verifiers);
            vm.startPrank(chosenVerifiers[i]);
            market.revealCommitment(0, agreements[verifierIndex], answers[verifierIndex], keccak256(abi.encodePacked("nonce", verifierIndex)));
            vm.stopPrank();
        }

        allVerifiersCollectRewards(verifiers, 0, roundNum);
        vm.stopPrank();

        RequestDetails memory requestUpdated = getRequestDetails(0);
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
}