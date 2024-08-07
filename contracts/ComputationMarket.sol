// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
//import "forge-std/console.sol";

contract CompNFT is ERC721, Ownable {
    uint256 public nextTokenId;

    constructor() ERC721("COMP_NFT", "CNFT") Ownable(msg.sender) {}

    function mint(address to) external onlyOwner returns (uint256) {
        uint256 tokenId = nextTokenId;
        _safeMint(to, tokenId);
        nextTokenId++;
        return tokenId;
    }

    function transferNFTContractOwnership(address newOwner) external onlyOwner {
        transferOwnership(newOwner);
    }
}

contract HandlerFunctionsCompMarket {
    function defaultVerifierVoteCounts(address add) external pure returns (uint256) {
        return add != address(0) ? 1 : 0;
    }
}

contract ComputationMarket {
    IERC20 public immutable compToken; // The ERC20 token used for payments
    //CompNFT public immutable compNFT; // The NFT used for storing provider payments
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

    /*struct CompNFT_Data {
        uint256 compNFT_id; // The ID of the NFT
        uint256 amountToPay; // Amount to be paid to the NFT Ower was request is verified
        uint256 requestID; // The ID of the request
        address originalProvider; // The original provider of the request
        bool hasBeenPaid;
    }*/

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

    // Structure representing the output of the getRoundDetails function
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

    uint256 public requestCount; // Total number of requests created
    
    // Mapping of request ID to Request struct
    mapping(uint256 => Request) public requests; 

    // Mapping of request ID and round number to RoundDetails struct
    mapping(uint256 => mapping(uint256 => RoundDetails)) public roundDetails;

    // Mapping of request ID, round number and verifier address to Verification struct
    mapping(uint256 => mapping(uint256 => mapping(address => Verification))) private verifications; 

    // List of private keys used for a request by the provider. Mapping of request ID and private key to whether it is used
    mapping(uint256 => mapping(uint256 => bool)) public providerPrivateKeys;

    // Mapping of request ID to NFT struct
    //mapping(uint256 => CompNFT_Data) public providerNFTs;

    // Mapping of NFT ID to request ID
    //mapping(uint256 => uint256) public NFTRequestID;

    // Mapping of number of requests successfully completed by provider
    //mapping(address => uint256) public providerSuccessfulRequestCount;

    // Mapping of number of requests failed by provider
    //mapping(address => uint256) public providerFailedRequestCount;

    // Mapping of number of requests picked up by provider
    //mapping(address => uint256) public providerPickedUpRequestCount;

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

    constructor(address compTokenAddress) {
        require(compTokenAddress != address(0), "Invalid token address");
        //require(compNFTAddress != address(0), "Invalid token address");
        compToken = IERC20(compTokenAddress); // Initialize the COMP token contract address
        //compNFT = CompNFT(compNFTAddress);
        handlerFunctions = new HandlerFunctionsCompMarket();
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
        require(allowance >= totalPayment, "Insufficient allowance available to conduct request");
        require(balance >= totalPayment, "Insufficient balance available to conduct request");

        require(computationDeadline > block.timestamp, "Computational deadline must be greater than the current time");
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

        require(compToken.transferFrom(msg.sender, address(this), totalPayment), "Payment failed");
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


    // Function to get request details
    function getRequestDetails(uint256 requestId) external view returns (Request memory) {
        return requests[requestId];
    }

    function getVerificationDetails(uint256 requestId, uint256 roundNum, address verifier) external view returns (Verification memory) {
        return verifications[requestId][roundNum][verifier];
    }

    function getRandomNumber(uint256 maxLimit) private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % maxLimit;
    }

    function getVoteCountForHashForRound(uint256 requestId, uint256 roundIndex, bytes32 voteHash) external view returns (uint256) {
        return roundDetails[requestId][roundIndex].votes[voteHash]; 
    }

    function getVerifiersTriggeredForRound(uint256 requestId, uint256 roundIndex) external view returns (bool) {
        return roundDetails[requestId][roundIndex].verifiersTriggered[msg.sender]; 
    }

    function getVerifiersAppliedForRound(uint256 requestId, uint256 roundIndex) external view returns (bool) {
        return roundDetails[requestId][roundIndex].verifiersApplied[msg.sender]; 
    }

    function getVerifiersChosenForRound(uint256 requestId, uint256 roundIndex) external view returns (bool) {
        return roundDetails[requestId][roundIndex].verifiersChosen[msg.sender]; 
    }

    function getRoundDetails(uint256 requestId, uint256 roundIndex) external view returns (RoundDetailsOutput memory) {
        RoundDetails storage roundDetailsOut = roundDetails[requestId][roundIndex];
        RoundDetailsOutput memory output = RoundDetailsOutput({
            roundIndex : roundDetailsOut.roundIndex,
            layerComputeIndex : roundDetailsOut.layerComputeIndex,
            verificationStartTime : roundDetailsOut.verificationStartTime,
            commitEndTime : roundDetailsOut.commitEndTime,
            providerRevealEndTime : roundDetailsOut.providerRevealEndTime,
            commitmentRevealEndTime : roundDetailsOut.commitmentRevealEndTime,
            majorityVoteHash : roundDetailsOut.majorityVoteHash,
            majorityCount : roundDetailsOut.majorityCount,
            mainProviderAnswerHash : roundDetailsOut.mainProviderAnswerHash,
            commitsSubmitted: roundDetailsOut.commitsSubmitted,
            commitsRevealed: roundDetailsOut.commitsRevealed,
            providerPrivateKey: roundDetailsOut.providerPrivateKey,
            providerInitialisationVector: roundDetailsOut.providerInitialisationVector

        });
        return output;
    }

    // Function to withdraw funds/cancel request in case of an error or cancellation. 
    // 1. This can only happen before anyone has picked up the request, OR
    // 2. Request has been picked up, and comptuation deadline has been reached, but not yet computed
    function cancelRequest(uint256 requestId) external {
        Request storage request = requests[requestId];
        require(msg.sender == request.consumer, "Only the consumer can withdraw funds");
        require(!request.completed, "Request already completed");
        if(request.mainProvider == address(0)) {
            request.completed = true;
            request.state = RequestStates.CANCELLED;
            require(compToken.transfer(request.consumer, request.totalPayment), "Error with Market. Failed to transfer");
            emit RequestCancelled(requestId);
            return;
        }
        require(request.computationDeadline < block.timestamp && !request.hasBeenComputed, "Computation deadline has not yet been reached");
        uint256 refundAmount = request.totalPayment + request.stake;
        request.completed = true;
        request.state = RequestStates.CANCELLED;
        require(compToken.transfer(request.consumer, refundAmount), "Error with Market. Failed to transfer");
        emit RequestCancelled(requestId);
    }

    // Function to select a request by a provider
    function selectRequest(uint256 requestId) external {
        Request storage request = requests[requestId];
        require(block.timestamp <= request.computationDeadline, "Computation deadline passed");
        require(request.mainProvider == address(0), "Provider already selected");

        uint256 stakeAmount = request.stake;
        uint256 allowance = compToken.allowance(msg.sender, address(this));
        uint256 balance = compToken.balanceOf(msg.sender);

        require(allowance >= stakeAmount, "Insufficient stake");
        require(balance >= stakeAmount, "Insufficient stake");

        request.mainProvider = msg.sender;
        request.state = RequestStates.PROVIDER_SELECTED_NOT_COMPUTED;
        
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

        require(compToken.transferFrom(msg.sender, address(this), stakeAmount), "Insufficient stake");
        emit ProviderSelected(requestId, msg.sender);
    }

    // Function to mark a request as completed by the provider
    function completeRequest(uint256 requestId, string[] memory outputFileURLs) external {
        Request storage request = requests[requestId];
        require(!request.completed, "Request has already been completed");
        require(block.timestamp <= request.computationDeadline, "Computation deadline passed");
        require(request.mainProvider == msg.sender, "Only chosen provider can complete request");
        request.hasBeenComputed = true;
        request.outputFileURLs = outputFileURLs;

        request.firstinitialisedTime = block.timestamp; // First time when the request was initialised
        initialiseRound(requestId);
        emit RequestCompletedByProvider(requestId, msg.sender);
        
    }

    // Function to initialise a round, and empty all verifiers/chosen verifier lists 
    function initialiseRound(uint256 requestId) internal {
        Request storage request = requests[requestId];
        require(request.mainProvider != address(0), "Main provider has not yet been selected");
        
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
        require(requestVerifierVoteCounts[requestId](msg.sender) > 0, "msg.sender is not allowed to apply for verification");
        require(block.timestamp >= request.firstinitialisedTime + 5, "Must wait 5 seconds before verifiers can apply");
        require(request.hasBeenComputed, "Request not yet computed");
        require(msg.sender != request.mainProvider, "The main provider cannot apply to become a verifier");
        require(request.verifiers.length < request.numVerifiers, "Verifier limit reached");
        require(request.state == RequestStates.CHOOSING_VERIFIERS, "Verifier cannot apply for verification. Request state must be in choosing verifiers state");

        uint256 allowance = compToken.allowance(msg.sender, address(this));
        uint256 balance = compToken.balanceOf(msg.sender);
        require(allowance >= request.paymentPerRoundForVerifiers, "Insufficient stake");
        require(balance >= request.paymentPerRoundForVerifiers, "Insufficient stake");
        require(request.verificationDeadline >= block.timestamp + (3 * request.timeAllocatedForVerification), "Not enough time to perform round before verification deadline");
        require(!roundDetails[requestId][request.roundIndex].verifiersApplied[msg.sender], "Verifier already applied");

        roundDetails[requestId][request.roundIndex].verifiersApplied[msg.sender] = true;
        request.verifiers.push(msg.sender);


        if (request.verifiers.length == request.numVerifiers) {
            emit VerificationSelectionStarted(requestId, request.layerComputeIndex);
        }
        require(compToken.transferFrom(msg.sender, address(this), request.paymentPerRoundForVerifiers), "Insufficient stake");
        emit VerificationApplied(requestId, msg.sender, request.layerComputeIndex);
    }

    // function called when verification deadline has passed and we do not have enough verifiers for the round to start
    function verificationDeadlinePassedForVeryfying(uint256 requestId, uint256 roundNum) public {
        Request storage request = requests[requestId];
        require(request.verificationDeadline < block.timestamp + (3 * request.timeAllocatedForVerification), "Verification deadline has not yet passed");
        require(roundDetails[requestId][roundNum].verifiersApplied[msg.sender], "Verifier has either already recieved stake, or did not apply for verification");
        require(!verifications[requestId][roundNum][msg.sender].verifierPaid, "Already been paid");

        verifications[requestId][roundNum][msg.sender].verifierPaid = true;
        require(compToken.transfer(msg.sender, request.paymentPerRoundForVerifiers), "Error in Market. Payment not sent");
    }

    // A verifier can only participate if they performed this trigger
    // Function to choose verifiers for the next round
    function chooseVerifiersForRequestTrigger(uint256 requestId) external {
        Request storage request = requests[requestId];
        require(request.verifiers.length == request.numVerifiers, "Verifier list has not been filled");
        require(request.hasBeenComputed, "Request has not been computed yet");
        require(request.verifiers.length >= request.numVerifiersSampleSize, "Not enough verifiers to choose from");
        require(request.verificationDeadline >= block.timestamp + (3 * request.timeAllocatedForVerification), "Not enough time to perform round before verification deadline");

        require(!roundDetails[requestId][request.roundIndex].verifiersTriggered[msg.sender], "Verifier has already triggered");
        roundDetails[requestId][request.roundIndex].verifiersTriggered[msg.sender] = true;

        if(request.verifierSelectionCount < request.numVerifiersSampleSize) {
            uint256 randNum = getRandomNumber(request.numVerifiers - request.verifierSelectionCount) + request.verifierSelectionCount;

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
            require(compToken.transfer(request.verifiers[request.verifierSelectionCount], request.paymentPerRoundForVerifiers), "Error in Market. Payment not sent");
            emit VerifierUnchosen(requestId, request.verifiers[request.verifierSelectionCount], request.layerComputeIndex, request.verifierSelectionCount);
        }
        request.verifierSelectionCount += 1;
        if(request.verifierSelectionCount == request.numVerifiersSampleSize) {
            startRound(requestId);
        }
    }

    // Function to return stake for verifiers if we do not have enough time to perform the next round 
    function returnStakeDueToTimeout(uint256 requestId, uint256 roundNum) external {
        Request storage request = requests[requestId];

        require(roundDetails[requestId][roundNum].verifiersApplied[msg.sender], "You are not the verifier for this round");
        require(request.verificationDeadline < block.timestamp + (3 * request.timeAllocatedForVerification), "Still enough time to perform round before verification deadline");
        require(request.state == ComputationMarket.RequestStates.CHOOSING_VERIFIERS, "Request Must be in choosing verifiers state");
        require(!verifications[requestId][roundNum][msg.sender].verifierPaid, "Already been paid");
        verifications[requestId][roundNum][msg.sender].verifierPaid = true;
        require(compToken.transfer(msg.sender, request.paymentPerRoundForVerifiers), "Error in Market. Payment not sent");
    }

    // Function to return stake for verifiers not chosen to participate in the next round
    function returnStake(uint256 requestId, uint256 roundNum) external {
        require(roundDetails[requestId][roundNum].verifiersTriggered[msg.sender], "You did not trigger");
        require(!roundDetails[requestId][roundNum].verifiersChosen[msg.sender], "Chosen verifeir cannot return stake");
        require(!verifications[requestId][roundNum][msg.sender].verifierPaid, "Already been paid");

        verifications[requestId][roundNum][msg.sender].verifierPaid = true;
        require(compToken.transfer(msg.sender, requests[requestId].paymentPerRoundForVerifiers), "Error in Market. Payment not sent"); 
    }

    // Function to start a round of verification
    function startRound(uint256 requestId) internal {
        Request storage request = requests[requestId];
        require(request.layerComputeIndex < request.layerCount, "All layers have been processed");
        require(request.verificationDeadline > block.timestamp + (3 * request.timeAllocatedForVerification), "Verification Deadline has passed to start a round");

        roundDetails[requestId][request.roundIndex].verificationStartTime = block.timestamp;
        roundDetails[requestId][request.roundIndex].commitEndTime = block.timestamp + request.timeAllocatedForVerification;
        roundDetails[requestId][request.roundIndex].providerRevealEndTime = roundDetails[requestId][request.roundIndex].commitEndTime + request.timeAllocatedForVerification;
        roundDetails[requestId][request.roundIndex].commitmentRevealEndTime = roundDetails[requestId][request.roundIndex].providerRevealEndTime + request.timeAllocatedForVerification;

        request.state = RequestStates.COMMITMENT_STATE;
        emit CommitmentPhaseStarted(requestId, block.timestamp, roundDetails[requestId][request.roundIndex].commitEndTime, request.layerComputeIndex);
    }

    // Function to submit a commitment by a verifier
    function submitCommitment(
        uint256 requestId,
        bytes32 computedHash
    ) external {
        Request storage request = requests[requestId];
        Verification storage verification = verifications[requestId][request.roundIndex][msg.sender];

        require(request.state == RequestStates.COMMITMENT_STATE, "Request not yet in commitment state");
        require(block.timestamp <= roundDetails[requestId][request.roundIndex].commitEndTime, "Commitment phase ended");
        require(roundDetails[requestId][request.roundIndex].verifiersChosen[msg.sender], "You are not the chosen verifier in this round");
        require(roundDetails[requestId][request.roundIndex].verifiersTriggered[msg.sender], "You did not trigger");


        verification.computedHash = computedHash;
        
        roundDetails[requestId][request.roundIndex].commitsSubmitted++;
        if(roundDetails[requestId][request.roundIndex].commitsSubmitted == request.numVerifiersSampleSize) {
            request.state = RequestStates.PROVIDER_REVEAL_STATE;
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
        require(msg.sender == request.mainProvider, "Only the main provider can reveal the key and hash");
        require(block.timestamp > roundDetails[requestId][request.roundIndex].commitEndTime ||
            request.state == RequestStates.PROVIDER_REVEAL_STATE, "Commitment phase not ended");
        require(block.timestamp <= roundDetails[requestId][request.roundIndex].providerRevealEndTime, "Provider reveal phase ended");
        require(!providerPrivateKeys[requestId][privateKey], "Private key has already been used");
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
        Request storage request = requests[requestId];
        require(block.timestamp > roundDetails[requestId][request.roundIndex].providerRevealEndTime ||
            request.state == RequestStates.COMMITMENT_REVEAL_STATE, "Provider reveal phase not ended");
        require(block.timestamp <= roundDetails[requestId][request.roundIndex].commitmentRevealEndTime, "Reveal phase ended");
        require(roundDetails[requestId][request.roundIndex].verifiersChosen[msg.sender], "You are not the chosen verifier");
        require(roundDetails[requestId][request.roundIndex].verifiersTriggered[msg.sender], "You did not trigger");

        Verification storage verification = verifications[requestId][request.roundIndex][msg.sender];
        require(!verification.revealed, "Commitment already revealed");
        require(keccak256(abi.encodePacked(answer, nonce, msg.sender)) == verification.computedHash, "Invalid reveal values");

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
        roundDetails[requestId][roundNum].commitsRevealed == request.numVerifiersSampleSize, "commitment stage has not yet completed");
        require(roundDetails[requestId][roundNum].verifiersChosen[msg.sender], "You are not the chosen verifier in this round");
        require(!verifications[requestId][roundNum][msg.sender].verifierPaid, "You have already been paid for verification");
        require(roundNum <= request.roundIndex, "round num must be less than or equal to request.roundIndex");
        require(roundNum >= 1, "Round number must be greater than or equal to 1");
        require(roundDetails[requestId][roundNum].verifiersTriggered[msg.sender], "You did not trigger");

        verifications[requestId][roundNum][msg.sender].verifierPaid = true; // Stops reentrancy and prevents double payment
        bytes32 majorityVoteHashForRound = roundDetails[requestId][roundNum].majorityVoteHash;
        if(majorityVoteHashForRound == bytes32(0)) {
            verifications[requestId][roundNum][msg.sender].verifierPaid = true;
            if (roundNum == request.roundIndex) {
                initialiseRound(requestId);
            }
            require(compToken.transfer(msg.sender, request.paymentPerRoundForVerifiers), "Error in Market. Transfer failed");
        } else {
            if (majorityVoteHashForRound == verifications[requestId][roundNum][msg.sender].voteHash) {
                
                uint256 reward = request.paymentPerRoundForVerifiers * request.numVerifiersSampleSize / roundDetails[requestId][roundNum].votes[majorityVoteHashForRound];
                uint256 stake = request.paymentPerRoundForVerifiers;
                verifications[requestId][roundNum][msg.sender].verifierPaid = true;
                require(compToken.transfer(msg.sender, reward + stake), "Error in Market. Transfer failed");
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
        require(request.state != RequestStates.UNSUCCESSFUL, "Request is unsuccessful");
        require(!request.completed, "Request is already completed");

        request.completed = true;

        /*address toPay = compNFT.ownerOf(providerNFTs[requestId].compNFT_id);
        providerNFTs[requestId].hasBeenPaid = true;*/
        address toPay = request.mainProvider;
        
        

        request.state = RequestStates.SUCCESS;
        //providerSuccessfulRequestCount[msg.sender]++;
        require(compToken.transfer(toPay, request.stake + request.paymentForProvider), "Error in Market. Transfer failed");
        emit ProviderResultSuccessfullyVerified(requestId);
    }

    // Provider calls this function, once the verification deadline has passed, and all rounds currently peformed agreed with the main provider
    function providerSuccessCall(uint256 requestId) public {
        Request storage request = requests[requestId];
        require(block.timestamp >= request.verificationDeadline && request.state != RequestStates.UNSUCCESSFUL && !request.completed, "Verification Deadline has not been passed.");
        request.completed = true;

        /*address toPay = compNFT.ownerOf(providerNFTs[requestId].compNFT_id);
        providerNFTs[requestId].hasBeenPaid = true;*/
        address toPay = request.mainProvider;

        request.state = RequestStates.SUCCESS;
        //providerSuccessfulRequestCount[msg.sender]++;
        require(compToken.transfer(toPay, request.stake + request.paymentForProvider), "Error in Market. Transfer failed");
        emit ProviderResultSuccessfullyVerified(requestId);
    }

    // Consumer gets to take the stake of the provider, if the provider did an incorrect calculation
    function providerFailure(uint256 requestId) public {
        Request storage request = requests[requestId];
        bytes32 majorityVoteHashForRound = roundDetails[requestId][request.roundIndex].majorityVoteHash;

        require(roundDetails[requestId][request.roundIndex].mainProviderAnswerHash != majorityVoteHashForRound &&
            request.state != RequestStates.UNSUCCESSFUL, "Request is already in unsuccessful state");

        request.state = RequestStates.UNSUCCESSFUL;

        request.completed = true;
        //providerFailedRequestCount[msg.sender]++;

        require(compToken.transfer(request.consumer, request.paymentForProvider + request.stake + request.totalPaymentForVerifiers - request.totalPaidForVerification), "Error in Market. Transfer failed");
        emit ProviderResultUnsuccessful(requestId);
    }

}
