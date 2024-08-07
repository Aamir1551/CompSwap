// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../contracts/ComputationMarket.sol";
import "../lib/forge-std/src/Test.sol";
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

    uint256 paymentForProvider = 1000 * 10 ** 18;
    uint256 paymentPerRoundForVerifiers = 500 * 10 ** 18;
    uint256 totalPaymentForVerifiers;
    uint256 numOperations = 3000;
    uint256 numVerifiers = 3;
    uint256 computationDeadline = 1 days;
    uint256 verificationDeadline = 2 days;
    uint256 timeAllocatedForVerification = 1 hours;
    uint256 numVerifiersSampleSize = 1; // For testing purposes
    uint256 constant PROVIDER_STAKE_PERCENTAGE = 15;

    struct RoundDetailsOutput {
        uint256 roundIndex;
        uint256 layerComputeIndex;
        uint256 verificationStartTime;
        uint256 commitEndTime;
        uint256 providerRevealEndTime;
        uint256 commitmentRevealEndTime;
        bytes32 majorityVoteHash;
        uint256 majorityCount;
        bytes32 mainProviderAnswerHash;
        uint256 commitsSubmitted;
        uint256 commitsRevealed;
        uint256 providerPrivateKey;
        uint256 providerInitialisationVector;
    }

    function getRoundDetails(uint256 requestId, uint256 roundNum) public returns (RoundDetailsOutput memory) {
        (
            uint256 roundIndex,
            uint256 layerComputeIndex,
            uint256 verificationStartTime,
            uint256 commitEndTime,
            uint256 providerRevealEndTime,
            uint256 commitmentRevealEndTime,
            bytes32 majorityVoteHash,
            uint256 majorityCount,
            bytes32 mainProviderAnswerHash,
            uint256 commitsSubmitted,
            uint256 commitsRevealed,
            uint256 providerPrivateKey,
            uint256 providerInitialisationVector
        ) = market.roundDetails(requestId, roundNum);
        return RoundDetailsOutput({
            roundIndex: roundIndex,
            layerComputeIndex: layerComputeIndex,
            verificationStartTime: verificationStartTime,
            commitEndTime: commitEndTime,
            providerRevealEndTime: providerRevealEndTime,
            commitmentRevealEndTime: commitmentRevealEndTime,
            majorityVoteHash: majorityVoteHash,
            majorityCount: majorityCount,
            mainProviderAnswerHash: mainProviderAnswerHash,
            commitsSubmitted: commitsSubmitted,
            commitsRevealed: commitsRevealed,
            providerPrivateKey: providerPrivateKey,
            providerInitialisationVector: providerInitialisationVector
        });
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


    function setUp() public {
        // Deploy the mock COMP token and the market contract
        compToken = new MockERC20();
        compNFT = new CompNFT();
        handler = new HandlerFunctionsCompMarket();
        market = new ComputationMarket(address(compToken), address(compNFT), address(handler));
        compNFT.transferNFTContractOwnership(address(market));

        // Distribute COMP tokens to test accounts
        compToken.transfer(consumer, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(provider, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(verifier1, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(verifier2, 1000000000000000000000000 * 10 ** compToken.decimals());
        compToken.transfer(verifier3, 1000000000000000000000000 * 10 ** compToken.decimals());


        // Label accounts for better readability in logs
        vm.label(consumer, "Consumer");
        vm.label(provider, "Provider");
        vm.label(verifier1, "Verifier1");
        vm.label(verifier2, "Verifier2");
        vm.label(verifier3, "Verifier3");

        // Calculate total payment for verifiers
        uint256 layerCount = (numOperations + 999) / 1000;
        totalPaymentForVerifiers = paymentPerRoundForVerifiers * numVerifiersSampleSize * layerCount;
    }

    function testCreateRequest() public {
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

        RequestDetails memory request = getRequestDetails(0);
        assertEq(request.consumer, consumer);
        assertEq(request.paymentForProvider, paymentForProvider);
        assertEq(request.numVerifiers, numVerifiers);
    }

    function testSelectRequest() public {
        testCreateRequest(); // Ensure a request is created

        vm.startPrank(provider);
        uint256 stakeAmount = (paymentForProvider * PROVIDER_STAKE_PERCENTAGE) / 100;
        compToken.approve(address(market), stakeAmount);
        market.selectRequest(0);
        vm.stopPrank();

        RequestDetails memory request = getRequestDetails(0);
        assertEq(request.mainProvider, provider);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.PROVIDER_SELECTED_NOT_COMPUTED));
    }

    function testCancelRequest() public {
        testCreateRequest(); // Ensure a request is created

        vm.startPrank(consumer);
        market.cancelRequest(0);
        vm.stopPrank();

        RequestDetails memory request = getRequestDetails(0);
        assertTrue(request.completed);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CANCELLED));
    }

    function testCompleteRequest() public {
        testSelectRequest(); // Ensure a request is selected

        vm.startPrank(provider);
        string[] memory outputFileURLs = new string[](1);
        outputFileURLs[0] = "output_file_url";
        market.completeRequest(0, outputFileURLs);
        vm.warp(block.timestamp + 6);
        vm.stopPrank();

        RequestDetails memory request = getRequestDetails(0);
        assertTrue(request.hasBeenComputed);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
    }

    function ApplyForVerification(address verifierAddress) public {
        vm.startPrank(verifierAddress);
        compToken.approve(address(market), paymentPerRoundForVerifiers);
        market.applyForVerificationForRequest(0);
        vm.stopPrank();
    }

    function testApplyForVerificationForRequest() public {
        testCompleteRequest(); // Ensure a request is completed

        ApplyForVerification(verifier1);
    }

    function triggerVerification(address verifierAddress) internal {
        vm.startPrank(verifierAddress);
        market.chooseVerifiersForRequestTrigger(0);
        vm.stopPrank();
    }

    function testSubmitCommitment() public {
        testApplyForVerificationForRequest(); // Ensure a verifier applied
        ApplyForVerification(verifier2);
        ApplyForVerification(verifier3);

        triggerVerification(verifier1);
        triggerVerification(verifier2);
        triggerVerification(verifier3);

        RequestDetails memory request = getRequestDetails(0);
        address[] memory verifiers = new address[](3);
        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;
        
        address[] memory chosenVerifiers = getVerifiersChosen(0, 1, verifiers);
        vm.startPrank(chosenVerifiers[0]);
        bytes32 computedHash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("answer")), keccak256(abi.encodePacked("nonce")), chosenVerifiers[0]));

        market.submitCommitment(0, computedHash);
        vm.stopPrank();

    }

    function testRevealProviderKeyAndHash() public {
        testSubmitCommitment(); // Ensure a commitment is submitted
        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        vm.startPrank(provider);
        uint256 privateKey = block.timestamp;
        uint256 initialisationVector = block.timestamp;

        bytes32 answerHash = keccak256(abi.encodePacked("answer_hash"));
        
        market.revealProviderKeyAndHash(0, privateKey, initialisationVector, answerHash);
        vm.stopPrank();

        RequestDetails memory request = getRequestDetails(0);
        RoundDetailsOutput memory roundDetails = getRoundDetails(0, 1);
        assertEq(roundDetails.mainProviderAnswerHash, keccak256(abi.encodePacked(answerHash, true)));
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.COMMITMENT_REVEAL_STATE));
    }

    function testRevealCommitment() public {
        
        address[] memory verifiers = new address[](3);
        verifiers[0] = verifier1;
        verifiers[1] = verifier2;
        verifiers[2] = verifier3;

        testRevealProviderKeyAndHash(); // Ensure provider reveals their key and hash
        vm.warp(block.timestamp + timeAllocatedForVerification + 1);

        RequestDetails memory request = getRequestDetails(0);
        address[] memory chosenVerifiers = getVerifiersChosen(0, 1, verifiers);

        vm.startPrank(chosenVerifiers[0]);
        bool agree = true;
        bytes32 answer = keccak256(abi.encodePacked("answer"));
        bytes32 nonce = keccak256(abi.encodePacked("nonce"));
        market.revealCommitment(0, agree, answer, nonce);
        vm.stopPrank();
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


    /*function testCalculateMajorityAndReward() public {
        testRevealCommitment(); // Ensure verifier reveals their commitment

        market.calculateMajorityAndReward(0);
        ComputationMarket.Request memory request = market.getRequestDetails(0);
        // Add more asserts to check the state and balances of verifiers and provider
    }*/
}