// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./COMPNFT.sol";
import "./HandlerFunctionsCompMarket.sol";

contract ComputationMarket {
    IERC20 public immutable compToken; // The ERC20 token used for payments
    CompNFT public immutable compNFT; // The NFT used for storing provider payments
    HandlerFunctionsCompMarket public immutable handlerFunctions;

    // The different states a request can be in
    enum RequestStates {NO_PROVIDER_SELECTED, PROVIDER_SELECTED_NOT_COMPUTED,
        CHOOSING_VERIFIERS, COMMITMENT_STATE, PROVIDER_REVEAL_STATE, 
        COMMITMENT_REVEAL_STATE, SUCCESS, UNSUCCESSFUL, CANCELLED}

    // Structure representing a computation request
    struct Request {
        address consumer; // The address of the consumer who created the request
        uint256 paymentForProvider; // Payment allocated for the provider
        uint256 totalPaymentForVerifiers; // Total payment allocated for verifiers
        uint256 numOperations; // Number of operations to be performed
        uint256 numVerifiers; // Number of verifiers needed
        string[] inputFileURLs; // URLs of input files
        string operationFileURL; // URL of the file with operations
        string[] outputFileURLs; // URL of the output files as provided by the main provider
        uint256 computationDeadline; // Deadline for the provider to complete computations
        uint256 verificationDeadline; // Deadline for verifiers to complete verifications
        uint256 totalPayment; // Total payment provided by the consumer
        bool completed; // Indicates if the request is completed. If true, the request has reached the end of its lifecycle
        bool hasBeenComputed; // Indicates if the computation has been completed
        uint256 numVerifiersSampleSize; // Number of verifiers sampled for each round
        address[] verifiers; // List of verifiers who applied for the current round
        address[] chosenVerifiers; // List of verifiers chosen for the current round
        address mainProvider; // The provider who accepted the request
        uint256 timeAllocatedForVerification; // Time allocated for each verification round
        uint256 layerCount; // Number of layers of operations
        uint256 layerComputeIndex; // Number of layers computed so far into the DAG
        uint256 roundIndex; // Number of rounds we have performed so far
        RequestStates state; // The state of the current request
        uint256 stake; // Amount staked by the provider
        uint256 paymentPerRoundForVerifiers; // Amount the consumer will pay for verification
        uint256 totalPaidForVerification; // Running total of amount paid to verifiers
        uint256 protocolVersion; // Version of the protocol we are following
        uint256 verifierSelectionCount; // Number of verifiers selected for the current round
        uint256 firstinitialisedTime; // Time when the request was first initialised
        uint256 layerSize; // Number of operations that are verified within each of the layers for each round
        bytes32 hashOfInputFiles; // Hash of the input files
    }

    // Structure representing a verification
    struct Verification {
        address verifier; // Address of the verifier
        bool agree; // Indicates if the verifier agrees with the provider's results
        bytes32 answer; // The result provided by the verifier
        bytes32 nonce; // Nonce used in the commitment
        bool revealed; // Indicates if the verifier has revealed their commitment
        bytes32 computedHash; // Hash of the commitment
        bytes32 voteHash; // Hash of the vote
        bool verifierPaid; // Indicates if the verifier has been paid
    }

    struct RoundDetails {
        mapping(bytes32 => uint256) votes; // Vote tally for the round. (voteHash => number of votes)
        mapping(address => bool) verifiersTriggered; // Map of verifiers and whether they have triggered the round
        mapping(address => bool) verifiersApplied; // Map of verifiers and whether they have applied for the round
        mapping(address => bool) verifiersChosen; // Map of verifiers and whether they have applied for the round

        uint256 roundIndex; // Sum of all rounds that are completed and retried so far
        uint256 layerComputeIndex; // The index into the DAG on which layer this round was operating on
        uint256 verificationStartTime; // Added to track when verification started
        uint256 commitEndTime; // Added to track end time for commitment phase
        uint256 providerRevealEndTime; // End time for provider to reveal their private key
        uint256 commitmentRevealEndTime; // Added to track end time for reveal phase
        bytes32 majorityVoteHash; // Majority vote for the round
        uint256 majorityCount; // Majority count for the majority vote for that round
        bytes32 mainProviderAnswerHash; // The answer hash of the main provider
        uint256 commitsSubmitted; // Number of commits provided
        uint256 commitsRevealed; // Number of commits revealed
        uint256 providerPrivateKey; // Private key of the provider
        uint256 providerInitialisationVector; // Initialisation vector of the provider
    }

    // Is verifier chosen
    function isVerifierChosenForRound(uint256 requestID, uint256 roundNum, address verifier) public view returns (bool) {
        return roundDetails[requestID][roundNum].verifiersChosen[verifier]; 
    }

    // Structure representing the output of the getRoundDetails function
    /*struct RoundDetailsOutput {
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
    }*/

    uint256 public requestCount; // Total number of requests created
    
    // Mapping of request ID to Request struct
    mapping(uint256 => Request) public requests; 

    // Mapping of request ID and round number to RoundDetails struct
    mapping(uint256 => mapping(uint256 => RoundDetails)) public roundDetails;

    // Mapping of request ID, round number and verifier address to Verification struct
    mapping(uint256 => mapping(uint256 => mapping(address => Verification))) public verifications; 

    // List of private keys used for a request by the provider. Mapping of request ID and private key to whether it is used
    mapping(uint256 => mapping(uint256 => bool)) public providerPrivateKeys;

    // Event emitted when a new request is created
    event RequestCreated(uint256 indexed requestId, address indexed consumer);
    
    // Event emitted when a provider is selected for a request
    event ProviderSelected(uint256 indexed requestId, address indexed provider);
    
    // Event emitted when a verifier is chosen
    event VerifierChosen(uint256 indexed requestId, address indexed verifier, uint256 indexed layerComputeIndex, uint256 verifierIndex);

    // Event emitted when a verifier is not chosen
    event VerifierUnchosen(uint256 indexed requestId, address indexed verifier, uint256 indexed layerComputeIndex, uint256 verifierIndex);

    // Event emitted when a commitment is submitted
    event CommitmentSubmitted(uint256 indexed requestId, address indexed verifier);
    
    // Event emitted when a result is completely verified
    event ProviderResultSuccessfullyVerified(uint256 indexed requestId);
    
    // Event emitted when the reveal phase of a round starts
    event RoundRevealStarted(uint256 indexed requestId);
    
    // Event emitted when a request is completed by the provider
    event RequestCompletedByProvider(uint256 indexed requestId, address indexed provider);
    
    // Event emitted when a verifier applies for verification
    event VerificationApplied(uint256 indexed requestId, address indexed verifier, uint256 indexed layerComputeIndex);

    // Event emitted when the commitment phase starts
    event CommitmentPhaseStarted(uint256 indexed requestId, uint256 startTime, uint256 endTime, uint256 layerComputeIndex);

    // Event emitted when the reveal phase ends
    event RevealVerificationDetails(uint256 indexed requestId, uint256 endTime, address indexed verifier);

    // Event emitted when the provider is slashed
    event ProviderSlashed(uint256 indexed requestId, address indexed provider);

    // Event emitted when the provider reveals their private key and hash
    event ProviderRevealed(uint256 indexed requestId, uint256 privateKey, uint256 initialisationVector, bytes32 answerHash);

    // Event emitted when a verifier submits their agreement or disagreement
    event VoteSubmitted(uint256 indexed requestId, address indexed verifier, bool agree);

    // Event emmited when their is no clear majority when counting votes
    event NoMajorityForRound(uint256 indexed requestId, uint256 layerComputeIndex);

    // Event emmited when request is cancelled
    event RequestCancelled(uint256 indexed requestId);

    // Event emmmited when a round is initialised
    event RoundInitialised(uint256 indexed requestId);

    // Event emitted to let verifiers know they can apply for verification
    event RoundStartedForVerificationSelection(uint256 indexed requestId, uint256 layerComputeIndex);

    // Event emmited when verifiers disagree with the provider
    event ProviderResultUnsuccessful(uint256 indexed requestId);

    // Event emitted when we have enough verifiers for the next round to start the selection of verifiers 
    event VerificationSelectionStarted(uint256 indexed requestId, uint256 layerComputeIndex);

    // Event emitted when provider alerts verifiers of a completion of request
    event AlertVerifiers(uint256 indexed requestId, address provider, uint256 verificationPrice, uint256 verificationDeadline, uint256 timeAllocatedForVerification, uint256 numVerifiers);

    // Event emitted when all commitments are revealed for a given round
    event AllCommitmentsRevealed(uint256 indexedrequestId, uint256 indexed roundNum);

    constructor(address compTokenAddress, address compNFTAddress, address HandlerFunctionsCompMarketAdd) {
        require(compTokenAddress != address(0), "Inval TKN ADD");
        require(compNFTAddress != address(0), "Inval NFT ADD");
        compToken = IERC20(compTokenAddress); // Initialize the COMP token contract address
        compNFT = CompNFT(compNFTAddress);
        handlerFunctions = HandlerFunctionsCompMarket(HandlerFunctionsCompMarketAdd);
    }

    // Function to create a new computation request
    function createRequestWithAllowedVerifiers(
        uint256 paymentForProvider, 
        uint256 paymentPerRoundForVerifiers, 
        uint256 numOperations, 
        uint256 numVerifiers, 
        string[] memory inputFileURLs, 
        string memory operationFileURL, 
        uint256 computationDeadline, 
        uint256 verificationDeadline, 
        uint256 timeAllocatedForVerification,
        uint256 numVerifiersSampleSize,
        uint256 protocolVersion,
        uint256 layerSize,
        bytes32 hashOfInputFiles,
        uint256 stake,
        function(address) external view returns (uint256) verifierVoteCount
    ) public {
        uint256 layerCount = (numOperations + layerSize - 1) / layerSize;
        uint256 totalPaymentForVerifiers = paymentPerRoundForVerifiers * numVerifiersSampleSize * layerCount;
        uint256 totalPayment = paymentForProvider + totalPaymentForVerifiers;

        uint256 allowance = compToken.allowance(msg.sender, address(this));
        uint256 balance = compToken.balanceOf(msg.sender);
        require(allowance >= totalPayment, "TF1");
        require(balance >= totalPayment, "TF2");

        require(computationDeadline > block.timestamp, "Compute < timestamp");
        require(verificationDeadline > computationDeadline + layerCount * (timeAllocatedForVerification * 3), "Verification deadline must be sufficient enough for all rounds required");
        require(numVerifiers >= numVerifiersSampleSize, "Not enough verifiers to choose from. numVerifiers must be greater than numVerifiersSampleSize");

        requestVerifierVoteCounts[requestCount] = verifierVoteCount;

        requests[requestCount] = Request({
            consumer: msg.sender,
            paymentForProvider: paymentForProvider,
            totalPaymentForVerifiers: totalPaymentForVerifiers,
            numOperations: numOperations,
            numVerifiers: numVerifiers,
            inputFileURLs: inputFileURLs,
            outputFileURLs: new string[](0),
            operationFileURL: operationFileURL,
            computationDeadline: computationDeadline,
            verificationDeadline: verificationDeadline,
            totalPayment: totalPayment,
            completed: false,
            hasBeenComputed: false,
            numVerifiersSampleSize: numVerifiersSampleSize,
            verifiers: new address[](0),
            chosenVerifiers: new address[](0),
            mainProvider: address(0),
            timeAllocatedForVerification: timeAllocatedForVerification,
            layerCount: layerCount,
            layerComputeIndex: 0,
            roundIndex: 0,
            state: RequestStates.NO_PROVIDER_SELECTED,
            stake: stake,
            paymentPerRoundForVerifiers: paymentPerRoundForVerifiers,
            totalPaidForVerification: 0,
            protocolVersion: protocolVersion,
            verifierSelectionCount: 0,
            firstinitialisedTime: 0 ,
            layerSize: layerSize,
            hashOfInputFiles: hashOfInputFiles
        });
        requestCount++;

        require(compToken.transferFrom(msg.sender, address(this), totalPayment), "TF3");
        emit RequestCreated(requestCount, msg.sender);
    }

    // Mapping of request ID to allowed verifier function handle
    mapping(uint256 => function(address) external view returns (uint256)) requestVerifierVoteCounts;

    function createRequest (
        uint256 paymentForProvider, 
        uint256 paymentPerRoundForVerifiers, 
        uint256 numOperations, 
        uint256 numVerifiers, 
        string[] memory inputFileURLs, 
        string memory operationFileURL, 
        uint256 computationDeadline, 
        uint256 verificationDeadline, 
        uint256 timeAllocatedForVerification,
        uint256 numVerifiersSampleSize,
        uint256 protocolVersion,
        uint256 layerSize,
        bytes32 hashOfInputFiles,
        uint256 stake) external {
            createRequestWithAllowedVerifiers(
                paymentForProvider, 
                paymentPerRoundForVerifiers, 
                numOperations, 
                numVerifiers, 
                inputFileURLs, 
                operationFileURL, 
                computationDeadline, 
                verificationDeadline,
                timeAllocatedForVerification,
                numVerifiersSampleSize,
                protocolVersion,
                layerSize,
                hashOfInputFiles,
                stake,
                handlerFunctions.defaultVerifierVoteCounts
            );
        }



    // Function to withdraw funds/cancel request in case of an error or cancellation. 
    // 1. This can only happen before anyone has picked up the request, OR
    // 2. Request has been picked up, and comptuation deadline has been reached, but not yet computed
    function cancelRequest(uint256 requestId) external {
        Request storage request = requests[requestId];
        require(msg.sender == request.consumer, "OC1"); // OC means only consumer
        require(!request.completed, "RC1"); // RC means request has already been completed
        if(request.mainProvider == address(0)) {
            request.completed = true;
            request.state = RequestStates.CANCELLED;
            require(compToken.transfer(request.consumer, request.totalPayment), "TF4");
            emit RequestCancelled(requestId);
            return;
        }
        require(request.computationDeadline < block.timestamp && !request.hasBeenComputed, "DNYR"); // DNYR means computation deadline has not yet been reached
        uint256 refundAmount = request.totalPayment + request.stake;
        request.completed = true;
        request.state = RequestStates.CANCELLED;
        require(compToken.transfer(request.consumer, refundAmount), "TF5");
        emit RequestCancelled(requestId);
    }

    // Function to select a request by a provider
    function selectRequest(uint256 requestId) external {
        Request storage request = requests[requestId];
        require(block.timestamp <= request.computationDeadline, "CDP1"); // CDP means computation deadline has already passed
        require(request.mainProvider == address(0), "PS1"); // PS Provider has already been selected

        uint256 stakeAmount = request.stake;
        uint256 allowance = compToken.allowance(msg.sender, address(this));
        uint256 balance = compToken.balanceOf(msg.sender);

        require(allowance >= stakeAmount, "Prov INS"); // Prov INS means provider has insufficient allowance
        require(balance >= stakeAmount, "Prov INS"); // Prov INS means provider has insufficient balance

        request.mainProvider = msg.sender;
        request.state = RequestStates.PROVIDER_SELECTED_NOT_COMPUTED;

        compNFT.mint(msg.sender, request.paymentForProvider, requestId);
        
        //providerPickedUpRequestCount[msg.sender]++;

        /*uint256 tokenId = compNFT.mint(msg.sender); // Mint the NFT to the provider
        providerNFTs[tokenId] = CompNFT_Data(
            {
                compNFT_id: tokenId, 
                amountToPay: request.paymentForProvider,
                requestID: requestId, 
                originalProvider: msg.sender, 
                hasBeenPaid: false
            });

        NFTRequestID[tokenId] = requestId;*/

        require(compToken.transferFrom(msg.sender, address(this), stakeAmount), "Sel: TF6");
        emit ProviderSelected(requestId, msg.sender);
    }

    // Function to mark a request as completed by the provider
    function completeRequest(uint256 requestId, string[] memory outputFileURLs) external {
        Request storage request = requests[requestId];
        require(!request.completed, "RC2"); // RC means request has already been completed
        require(block.timestamp <= request.computationDeadline, "CDP2"); // CDP means computation deadline has passed
        require(request.mainProvider == msg.sender, "NP1"); // NP means msg.sender is not the main provider
        request.hasBeenComputed = true;
        request.outputFileURLs = outputFileURLs;

        request.firstinitialisedTime = block.timestamp; // First time when the request was initialised
        initialiseRound(requestId);
        emit RequestCompletedByProvider(requestId, msg.sender);
        
    }

    // Function to initialise a round, and empty all verifiers/chosen verifier lists 
    function initialiseRound(uint256 requestId) internal {
        Request storage request = requests[requestId];
        require(request.mainProvider != address(0), "!MPS"); // !MPS means main provider has not picked up the request
        
        request.verifiers = new address[](0);
        request.chosenVerifiers = new address[](0);
        request.state = RequestStates.CHOOSING_VERIFIERS;

        request.roundIndex += 1;
        request.verifierSelectionCount = 0;

        emit RoundStartedForVerificationSelection(requestId, request.layerComputeIndex);
        emit AlertVerifiers(requestId, msg.sender, request.paymentPerRoundForVerifiers, request.verificationDeadline, request.timeAllocatedForVerification, request.numVerifiers);
        emit RoundInitialised(requestId);
    }

    // Function for verifiers to apply for verification
    function applyForVerificationForRequest(uint256 requestId) external {
        Request storage request = requests[requestId];
        require(requestVerifierVoteCounts[requestId](msg.sender) > 0, "Verifier Blocked");
        require(block.timestamp >= request.firstinitialisedTime + 5, "Try again in 5");
        require(request.hasBeenComputed, "RNYC2");
        require(msg.sender != request.mainProvider, "V!=P"); // V!=P means main provider cannot apply for verification
        require(request.verifiers.length < request.numVerifiers, "LR1"); // LR means limit has been reached
        require(request.state == RequestStates.CHOOSING_VERIFIERS, "S!=CV"); // S!=CV means state is not choosing verifiers state

        uint256 allowance = compToken.allowance(msg.sender, address(this));
        uint256 balance = compToken.balanceOf(msg.sender);
        require(allowance >= request.paymentPerRoundForVerifiers, "TF7");
        require(balance >= request.paymentPerRoundForVerifiers, "TF8");
        require(request.verificationDeadline >= block.timestamp + (3 * request.timeAllocatedForVerification), "DP1");
        require(!roundDetails[requestId][request.roundIndex].verifiersApplied[msg.sender], "VA1"); // VA means verifier already applied

        roundDetails[requestId][request.roundIndex].verifiersApplied[msg.sender] = true;
        request.verifiers.push(msg.sender);


        if (request.verifiers.length == request.numVerifiers) {
            emit VerificationSelectionStarted(requestId, request.layerComputeIndex);
        }
        require(compToken.transferFrom(msg.sender, address(this), request.paymentPerRoundForVerifiers), "TF9");
        emit VerificationApplied(requestId, msg.sender, request.layerComputeIndex);
    }

    // function called when verification deadline has passed and we do not have enough verifiers for the round to start
    function verificationDeadlinePassedForVeryfying(uint256 requestId, uint256 roundNum) public {
        Request memory request = requests[requestId];
        require(request.verificationDeadline < block.timestamp + (3 * request.timeAllocatedForVerification), "NDP1"); // NDP means not deadline passed
        require(roundDetails[requestId][roundNum].verifiersApplied[msg.sender], "VDA1"); // VDA means Verifier did not apply
        require(!verifications[requestId][roundNum][msg.sender].verifierPaid, "AP1");

        verifications[requestId][roundNum][msg.sender].verifierPaid = true;
        require(compToken.transfer(msg.sender, request.paymentPerRoundForVerifiers), "TF10");
    }

    // A verifier can only participate if they performed this trigger
    // Function to choose verifiers for the next round
    function chooseVerifiersForRequestTrigger(uint256 requestId) external {
        Request storage request = requests[requestId];
        require(request.verifiers.length == request.numVerifiers, "AF1"); // AF means all filled
        require(request.hasBeenComputed, "RNYC1"); // RNYC Request not yet completed
        require(request.verifiers.length >= request.numVerifiersSampleSize, "NEV1"); // NEV means not enough verifiers
        require(request.verificationDeadline >= block.timestamp + (3 * request.timeAllocatedForVerification), "DP2");

        require(!roundDetails[requestId][request.roundIndex].verifiersTriggered[msg.sender], "VT1"); // VT means verifier has already triggered
        roundDetails[requestId][request.roundIndex].verifiersTriggered[msg.sender] = true;

        if(request.verifierSelectionCount < request.numVerifiersSampleSize) {
            uint256 randNum = handlerFunctions.getRandomNumber(request.numVerifiers - request.verifierSelectionCount) + request.verifierSelectionCount;

            address swap1 = request.verifiers[randNum]; // Swap 1 is what we have chosen
            address swap2 = request.verifiers[request.verifierSelectionCount];

            request.verifiers[randNum] = swap2;
            request.verifiers[request.verifierSelectionCount] = swap1;
            roundDetails[requestId][request.roundIndex].verifiersChosen[swap1] = true;
            request.chosenVerifiers.push(request.verifiers[request.verifierSelectionCount]);
            request.totalPaidForVerification += request.paymentPerRoundForVerifiers;
            emit VerifierChosen(requestId, request.verifiers[request.verifierSelectionCount], request.layerComputeIndex, request.verifierSelectionCount);
        } else {
            verifications[requestId][request.roundIndex][request.verifiers[request.verifierSelectionCount]].verifierPaid = true;
            require(compToken.transfer(request.verifiers[request.verifierSelectionCount], request.paymentPerRoundForVerifiers), "TF11");
            emit VerifierUnchosen(requestId, request.verifiers[request.verifierSelectionCount], request.layerComputeIndex, request.verifierSelectionCount);
        }
        request.verifierSelectionCount += 1;
        if(request.verifierSelectionCount == request.numVerifiersSampleSize) {
            startRound(requestId);
        }
    }

    // Function to return stake for verifiers if we do not have enough time to perform the next round 
    function returnStakeDueToTimeout(uint256 requestId, uint256 roundNum) external {
        Request memory request = requests[requestId];

        require(roundDetails[requestId][roundNum].verifiersApplied[msg.sender], "NCV1");
        require(request.verificationDeadline < block.timestamp + (3 * request.timeAllocatedForVerification), "DP3");
        require(request.state == ComputationMarket.RequestStates.CHOOSING_VERIFIERS, "S!=CV");
        require(!verifications[requestId][roundNum][msg.sender].verifierPaid, "AP"); // AP means already paid
        verifications[requestId][roundNum][msg.sender].verifierPaid = true;
        require(compToken.transfer(msg.sender, request.paymentPerRoundForVerifiers), "TF12");
    }

    // Function to return stake for verifiers not chosen to participate in the next round
    function returnStake(uint256 requestId, uint256 roundNum) external {
        require(roundDetails[requestId][roundNum].verifiersTriggered[msg.sender], "Ret Stake: DNT");
        require(!roundDetails[requestId][roundNum].verifiersChosen[msg.sender]);
        require(!verifications[requestId][roundNum][msg.sender].verifierPaid, "Double Payment"); // AP means already paid

        verifications[requestId][roundNum][msg.sender].verifierPaid = true;
        require(compToken.transfer(msg.sender, requests[requestId].paymentPerRoundForVerifiers), "TF13"); 
    }

    // Function to start a round of verification
    function startRound(uint256 requestId) internal {
        Request memory request = requests[requestId];
        require(request.layerComputeIndex < request.layerCount, "ALP"); // ALP means all layers have been computed
        require(request.verificationDeadline > block.timestamp + (3 * request.timeAllocatedForVerification), "DP4"); // DP means deadline passed

        roundDetails[requestId][request.roundIndex].verificationStartTime = block.timestamp;
        roundDetails[requestId][request.roundIndex].commitEndTime = block.timestamp + request.timeAllocatedForVerification;
        roundDetails[requestId][request.roundIndex].providerRevealEndTime = roundDetails[requestId][request.roundIndex].commitEndTime + request.timeAllocatedForVerification;
        roundDetails[requestId][request.roundIndex].commitmentRevealEndTime = roundDetails[requestId][request.roundIndex].providerRevealEndTime + request.timeAllocatedForVerification;

        requests[requestId].state = RequestStates.COMMITMENT_STATE;
        emit CommitmentPhaseStarted(requestId, block.timestamp, roundDetails[requestId][request.roundIndex].commitEndTime, request.layerComputeIndex);
    }

    // Function to submit a commitment by a verifier
    function submitCommitment(
        uint256 requestId,
        bytes32 computedHash
    ) external {
        Request memory request = requests[requestId];

        require(request.state == RequestStates.COMMITMENT_STATE, "S!=CS"); // S!=CS means request not yet in commitment state
        require(block.timestamp <= roundDetails[requestId][request.roundIndex].commitEndTime, "CPE"); // CPE means commit phase ended
        require(roundDetails[requestId][request.roundIndex].verifiersChosen[msg.sender], "NCV2"); // NCV means not chosen verifier
        require(roundDetails[requestId][request.roundIndex].verifiersTriggered[msg.sender], "DNT"); // DNT means did not trigger


        verifications[requestId][request.roundIndex][msg.sender].computedHash = computedHash;
        
        roundDetails[requestId][request.roundIndex].commitsSubmitted++;
        if(roundDetails[requestId][request.roundIndex].commitsSubmitted == request.numVerifiersSampleSize) {
            requests[requestId].state = RequestStates.PROVIDER_REVEAL_STATE;
        }

        emit CommitmentSubmitted(requestId, msg.sender);
    }

    // Function to reveal the provider's private key and hash of the answer
    // The answer hash is equal to: keccak256(abi.encode(agree, answer)), where agree is true
    function revealProviderKeyAndHash(
        uint256 requestId,
        uint256 privateKey,
        uint256 initialisationVector,
        bytes32 answerHash
    ) external {
        Request storage request = requests[requestId];
        require(msg.sender == request.mainProvider, "OMP"); // OMP means only main provider
        require(block.timestamp > roundDetails[requestId][request.roundIndex].commitEndTime ||
            request.state == RequestStates.PROVIDER_REVEAL_STATE, "CPNE"); // CPNE means Commitment Phase Not Ended
        require(block.timestamp <= roundDetails[requestId][request.roundIndex].providerRevealEndTime, "PRPE"); // PRPE means Provider Reveal Phase Ended
        require(!providerPrivateKeys[requestId][privateKey], "PKIU"); // PKIU means private key has already been used
        roundDetails[requestId][request.roundIndex].mainProviderAnswerHash = keccak256(abi.encodePacked(answerHash, true));
        roundDetails[requestId][request.roundIndex].providerInitialisationVector = initialisationVector;
        roundDetails[requestId][request.roundIndex].providerPrivateKey = privateKey;
        providerPrivateKeys[requestId][privateKey] = true;

        request.state = RequestStates.COMMITMENT_REVEAL_STATE;

        emit ProviderRevealed(requestId, privateKey, initialisationVector, answerHash);
    }

    event RevealCommitmentFailed(uint256 requestId, bytes32 newHashComputed, bytes32 oldHashComputed);

    function revealCommitment(
        uint256 requestId,
        bool agree,
        bytes32 answer,
        bytes32 nonce
    ) external {
        Request memory request = requests[requestId];
        require(block.timestamp > roundDetails[requestId][request.roundIndex].providerRevealEndTime ||
            request.state == RequestStates.COMMITMENT_REVEAL_STATE, "PRPNE"); // PRPNE means provider reveal phase not ended
        require(block.timestamp <= roundDetails[requestId][request.roundIndex].commitmentRevealEndTime, "RPE"); // RPE means reveal phase ended
        require(roundDetails[requestId][request.roundIndex].verifiersChosen[msg.sender], "NCV3"); // NCV means not chosen verifier
        require(roundDetails[requestId][request.roundIndex].verifiersTriggered[msg.sender], "DNT"); // DNT means did not trigger

        Verification storage verification = verifications[requestId][request.roundIndex][msg.sender];
        require(!verification.revealed, "CAR"); // CAR means commitment already revealed
        require(keccak256(abi.encodePacked(answer, nonce, msg.sender)) == verification.computedHash, "IRV"); // Means invalid reveal values

        bytes32 voteHash = keccak256(abi.encodePacked(answer, agree));

        verification.agree = agree;
        verification.answer = answer;
        verification.nonce = nonce;
        verification.revealed = true;
        verification.verifier = msg.sender;
        verification.voteHash = voteHash;

        RoundDetails storage round = roundDetails[requestId][request.roundIndex];

        round.votes[voteHash] += requestVerifierVoteCounts[requestId](msg.sender);
        //round.votes[voteHash]++;

        if (round.votes[voteHash] == round.majorityCount) {
            roundDetails[requestId][request.roundIndex].majorityVoteHash = bytes32(0);
        } else if (round.votes[voteHash] > round.majorityCount) {
            roundDetails[requestId][request.roundIndex].majorityVoteHash = voteHash;
            round.majorityCount = round.votes[voteHash];
        }

        roundDetails[requestId][request.roundIndex].commitsRevealed++;
        emit RevealVerificationDetails(requestId, block.timestamp, msg.sender);

        if(roundDetails[requestId][request.roundIndex].commitsRevealed == request.numVerifiersSampleSize) {
            emit AllCommitmentsRevealed(requestId, request.roundIndex);
        }
    }

    // Function to calculate the majority vote and allow msg.sender to extract reward if msg.sender vote agreed with majority of the voters
    function calculateMajorityAndReward(uint256 requestId, uint256 roundNum) public {
        Request storage request = requests[requestId];

        require(block.timestamp >= roundDetails[requestId][roundNum].commitmentRevealEndTime ||
        roundDetails[requestId][roundNum].commitsRevealed == request.numVerifiersSampleSize, "CSNC"); // CSNC means commitment not yet completed
        require(roundDetails[requestId][roundNum].verifiersChosen[msg.sender], "NCV4"); // NCV means not chosen verifier
        require(!verifications[requestId][roundNum][msg.sender].verifierPaid, "DP5"); // DP means double payment
        require(roundNum <= request.roundIndex, "RI");
        require(roundNum >= 1, "RI"); // RI means round number is invalid
        require(roundDetails[requestId][roundNum].verifiersTriggered[msg.sender], "NT1");

        verifications[requestId][roundNum][msg.sender].verifierPaid = true; // Stops reentrancy and prevents double payment
        bytes32 majorityVoteHashForRound = roundDetails[requestId][roundNum].majorityVoteHash;
        if(majorityVoteHashForRound == bytes32(0)) {
            verifications[requestId][roundNum][msg.sender].verifierPaid = true;
            if (roundNum == request.roundIndex) {
                initialiseRound(requestId);
            }
            require(compToken.transfer(msg.sender, request.paymentPerRoundForVerifiers), "TF14");
        } else {
            if (majorityVoteHashForRound == verifications[requestId][roundNum][msg.sender].voteHash) {
                
                uint256 reward = request.paymentPerRoundForVerifiers * request.numVerifiersSampleSize / roundDetails[requestId][roundNum].votes[majorityVoteHashForRound];
                uint256 stake = request.paymentPerRoundForVerifiers;
                verifications[requestId][roundNum][msg.sender].verifierPaid = true;
                require(compToken.transfer(msg.sender, reward + stake), "TF15");
            }
            // provider doesn't match with majority vote, then provider failure
            if(request.roundIndex == roundNum) {
                if(roundDetails[requestId][roundNum].mainProviderAnswerHash != majorityVoteHashForRound) {
                    if(request.state != RequestStates.UNSUCCESSFUL) {
                        providerFailure(requestId);
                    }
                } else {
                    if(request.layerComputeIndex == request.layerCount - 1) {
                        request.layerComputeIndex++;
                        providerSuccess(requestId);
                    }
                    else if(request.layerComputeIndex < request.layerCount) {
                        request.layerComputeIndex++;
                        initialiseRound(requestId);
                    }
                }
            }
        }
    }

    // Function is triggered automatically once all verification rounds are completed
    function providerSuccess(uint256 requestId) internal {
        Request storage request = requests[requestId];
        require(request.state != RequestStates.UNSUCCESSFUL, "RIC1");
        require(!request.completed, "RIC2");

        request.completed = true;

        /*address toPay = compNFT.ownerOf(compNFT.getNFTData(requestId).compNFT_id);
        compNFT.providerNFTs[requestId].hasBeenPaid = true;
        compNFT.providerSuccessfulRequestCount[msg.sender]++;*/

        address toPay = compNFT.providerSuccess(requestId);

        request.state = RequestStates.SUCCESS;
        require(compToken.transfer(toPay, request.stake + request.paymentForProvider), "TF16");
        emit ProviderResultSuccessfullyVerified(requestId);
    }

    // Provider calls this function, once the verification deadline has passed, and all rounds currently peformed agreed with the main provider
    function providerSuccessCall(uint256 requestId) public {
        Request storage request = requests[requestId];
        require(block.timestamp >= request.verificationDeadline && request.state != RequestStates.UNSUCCESSFUL && !request.completed, "RIC || time < ver");
        request.completed = true;

        
        /*address toPay = compNFT.ownerOf(compNFT.getNFTData(requestId).compNFT_id);
        compNFT.providerNFTs[requestId].hasBeenPaid = true;
        compNFT.providerSuccessfulRequestCount[msg.sender]++;*/

        address toPay = compNFT.providerSuccess(requestId);

        request.state = RequestStates.SUCCESS;
        require(compToken.transfer(toPay, request.stake + request.paymentForProvider), "TF17"); // TF means transfer failed
        emit ProviderResultSuccessfullyVerified(requestId);
    }

    // Consumer gets to take the stake of the provider, if the provider did an incorrect calculation
    function providerFailure(uint256 requestId) public {
        Request storage request = requests[requestId];
        bytes32 majorityVoteHashForRound = roundDetails[requestId][request.roundIndex].majorityVoteHash;

        require(roundDetails[requestId][request.roundIndex].mainProviderAnswerHash != majorityVoteHashForRound &&
            request.state != RequestStates.UNSUCCESSFUL, "RIU || NMV"); // RIU means round is in unsuccessful state. NMV means not majority vote

        request.state = RequestStates.UNSUCCESSFUL;

        request.completed = true;
        compNFT.providerFailure(requestId);

        require(compToken.transfer(request.consumer, request.paymentForProvider + request.stake + request.totalPaymentForVerifiers - request.totalPaidForVerification), "TF18"); // TF means tranfer failed
        emit ProviderResultUnsuccessful(requestId);
    }

}
