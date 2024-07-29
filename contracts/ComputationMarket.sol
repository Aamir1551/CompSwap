// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ComputationMarket {
    IERC20 public compToken; // The ERC20 token used for payments

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
        address[] verifiers; // List of verifiers who applied
        address[] chosenVerifiers; // List of verifiers chosen for the round
        address mainProvider; // The provider who accepted the request
        uint256 timeAllocatedForVerification; // Time allocated for each verification round
        uint256 layerCount; // Number of layers of operations
        uint256 layerComputeIndex; // Current layer being computed
        uint256 verificationStartTime; // Added to track when verification started
        uint256 commitEndTime; // Added to track end time for commitment phase
        uint256 commitmentRevealEndTime; // Added to track end time for reveal phase
        uint256 providerRevealEndTime; // End time for provider to reveal their private key
        uint256 roundIndex; // Sum of all rounds that are completed and retried
        bytes32 mainProviderAnswerHash; // The answer hash of the main provider
        RequestStates state; // The state of the current request
        uint256 stake; // Amount staked by the provider
        uint256 paymentPerRoundForVerifiers; // Amount the consumer will pay for verification
        uint256 totalPaidForVerification; // Running total of amount paid to verifiers
        uint256 protocolVersion; // Version of the protocol we are following
        bytes32 majorityVoteHash;
        uint256 majorityCount;
        bool existMajority;
    }

    // Structure representing a verification
    struct Verification {
        address verifier; // Address of the verifier
        bool agree; // Indicates if the verifier agrees with the provider's results
        bytes32 answer; // The result provided by the verifier
        bytes32 nonce; // Nonce used in the commitment
        bool revealed; // Indicates if the verifier has revealed their commitment
        bytes32 computedHash; // Hash of the commitment
    }

    uint256 public requestCount; // Total number of requests created
    uint256 public constant PROVIDER_STAKE_PERCENTAGE = 10; // Percentage of payment provider needs to stake
    uint256 public constant MIN_VERIFIERS = 3; // Minimum number of verifiers required
    
    // Mapping of request ID to Request struct
    mapping(uint256 => Request) public requests; 

    // Mapping of request ID and verifier address to Verification struct
    mapping(uint256 => mapping(address => Verification)) public verifications; 

    // State variable to store votes for each request and for each round. (requestId, voteHash, roundNum) => number of votes
    mapping(uint256 => mapping(bytes32 => mapping(uint256 => uint256))) private votes;

    // State variable to store vote addresses for each request and for each round. (requestId, voteHash, roundNum) => addresses of those that voted
    mapping(uint256 => mapping(bytes32 => mapping(uint256 => address[]))) private voteAddresses;

    // Event emitted when a new request is created
    event RequestCreated(uint256 indexed requestId, address indexed consumer);
    
    // Event emitted when a provider is selected for a request
    event ProviderSelected(uint256 indexed requestId, address indexed provider);
    
    // Event emitted when a verifier is chosen
    event VerifierChosen(uint256 indexed requestId, address indexed verifier, uint256 indexed layerComputeIndex);

    // Event emitted when a commitment is submitted
    event CommitmentSubmitted(uint256 indexed requestId, address indexed verifier);
    
    // Event emitted when a result is completely verified
    event ProviderResultSuccessfullyVerified(uint256 indexed requestId);
    
    // Event emitted when the reveal phase of a round starts
    event RoundRevealStarted(uint256 indexed requestId);
    
    // Event emitted when a request is completed by the provider
    event RequestCompleted(uint256 indexed requestId, address indexed provider);
    
    // Event emitted when a verifier applies for verification
    event VerificationApplied(uint256 indexed requestId, address indexed verifier, uint256 indexed layerComputeIndex);

    // Event emitted when the commitment phase starts
    event CommitmentPhaseStarted(uint256 indexed requestId, uint256 startTime, uint256 endTime, uint256 layerComputeIndex);

    // Event emitted when the reveal phase ends
    event RevealVerificationDetails(uint256 indexed requestId, uint256 endTime, address indexed verifier);

    // Event emitted when the provider is slashed
    event ProviderSlashed(uint256 indexed requestId, address indexed provider);

    // Event emitted when the provider reveals their private key and hash
    event ProviderRevealed(uint256 indexed requestId, bytes32 privateKey, bytes32 answerHash);

    // Event emitted when a verifier submits their agreement or disagreement
    event VoteSubmitted(uint256 indexed requestId, address indexed verifier, bool agree);

    // Event emmited when their is no clear majority when counting votes
    event NoMajorityForRound(uint256 indexed requestId, uint256 layerComputeIndex);

    // Event emmited when request is cancelled
    event requestCancelled(uint256 indexed requestId);

    // Event emmmited when a round is initialised
    event RoundInitialised(uint256 indexed requestId);

    // Event emitted to let verifiers know they can apply for verification
    event RoundStartedForVerificationSelection(uint256 indexed requestId, uint256 layerComputeIndex);

    // Event emmited when verifiers disagree with the provider
    event ProviderResultUnsuccessful(uint256 indexed requestId);

    constructor(address compTokenAddress) {
        require(compTokenAddress != address(0), "Invalid token address");
        compToken = IERC20(compTokenAddress); // Initialize the COMP token contract address
    }

    // Function to create a new computation request
    function createRequest(
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
        uint256 protocolVersion
    ) external {
        uint256 layerCount = (numOperations + 999) / 1000;
        uint256 totalPaymentForVerifiers = paymentPerRoundForVerifiers * numVerifiersSampleSize * layerCount;
        uint256 totalPayment = paymentForProvider + totalPaymentForVerifiers;

        require(numVerifiers >= MIN_VERIFIERS, "At least 3 verifiers required");

        uint256 allowance = compToken.allowance(msg.sender, address(this));
        uint256 balance = compToken.balanceOf(msg.sender);
        require(allowance >= totalPayment, "Insufficient allowance available to conduct request");
        require(balance >= totalPayment, "Insufficient balance available to conduct request");
        require(compToken.transferFrom(msg.sender, address(this), totalPayment), "Payment failed");

        require(computationDeadline > block.timestamp, "Computational deadline must be greater than the current time");
        require(verificationDeadline > computationDeadline + layerCount * (timeAllocatedForVerification * 3), "Verification deadline must be sufficient enough for all rounds required");
        require(numVerifiers >= numVerifiersSampleSize, "Not enough verifiers to choose from. numVerifiers must be greater than numVerifiersSampleSize");

        requests[requestCount] = Request({
            consumer: msg.sender,
            paymentForProvider: paymentForProvider,
            totalPaymentForVerifiers: totalPaymentForVerifiers,
            numOperations: numOperations,
            numVerifiers: numVerifiers,
            inputFileURLs: inputFileURLs,
            outputFileURLs: new string[](0),
            operationFileURL: operationFileURL,
            computationDeadline: block.timestamp + computationDeadline,
            verificationDeadline: block.timestamp + verificationDeadline,
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
            verificationStartTime: 0,
            commitEndTime: 0,
            commitmentRevealEndTime: 0,
            providerRevealEndTime: 0,
            roundIndex: 0,
            mainProviderAnswerHash: 0,
            state: RequestStates.NO_PROVIDER_SELECTED,
            stake: (paymentForProvider * PROVIDER_STAKE_PERCENTAGE) / 100,
            paymentPerRoundForVerifiers: paymentPerRoundForVerifiers,
            totalPaidForVerification: 0,
            protocolVersion: protocolVersion,
            majorityVoteHash: bytes32(0),
            majorityCount: 0,
            existMajority: true
        });
        requestCount++;

        emit RequestCreated(requestCount, msg.sender);
    }

    // Function to get request details
    function getRequestDetails(uint256 requestId) external view returns (Request memory) {
        return requests[requestId];
    }

    // Function to get verification details
    function getVerificationDetails(uint256 requestId, address verifier) external view returns (Verification memory) {
        return verifications[requestId][verifier];
    }

    function getRandomNumbers(uint256 maxLimit, uint256 count) private view returns (uint256[] memory) {
        uint256[] memory randomNumbers = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            randomNumbers[i] = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, i))) % maxLimit;
        }
        return randomNumbers;
    }

    // Function to withdraw funds/cancel request in case of an error or cancellation. 
    // 1. This can only happen before anyone has picked up the request, OR
    // 2. Request has been picked up, and comptuation deadline has been reached, but not yet computed
    function cancelRequest(uint256 requestId) external {
        Request storage request = requests[requestId];
        require(msg.sender == request.consumer, "Only the consumer can withdraw funds");
        require(!request.completed, "Request already completed");
        if(request.mainProvider == address(0)) {
            compToken.transfer(request.consumer, request.totalPayment);
            request.completed = true;
            request.state = RequestStates.CANCELLED;
            emit requestCancelled(requestId);
            return;
        }
        require(request.computationDeadline < block.timestamp && !request.hasBeenComputed, "Computation deadline has not yet been reached");
        uint256 refundAmount = request.totalPayment + request.stake;
        compToken.transfer(request.consumer, refundAmount);
        request.completed = true;
        request.state = RequestStates.CANCELLED;
        emit requestCancelled(requestId);
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

        require(compToken.transferFrom(msg.sender, address(this), stakeAmount), "Insufficient stake");

        request.mainProvider = msg.sender;
        request.state = RequestStates.PROVIDER_SELECTED_NOT_COMPUTED;

        emit ProviderSelected(requestId, msg.sender);
    }

    // Function to mark a request as completed by the provider
    function completeRequest(uint256 requestId, string[] memory outputFileURLs) external {
        Request storage request = requests[requestId];
        require(block.timestamp <= request.computationDeadline, "Computation deadline passed");
        require(request.mainProvider == msg.sender, "Only chosen provider can complete request");
        request.hasBeenComputed = true;
        request.outputFileURLs = outputFileURLs;
        emit RequestCompleted(requestId, msg.sender);
        initialiseRound(requestId);
    }

    // Function to initialise a round, and empty all verifiers/chosen verifier lists 
    function initialiseRound(uint256 requestId) internal {
        Request storage request = requests[requestId];
        require(request.mainProvider != address(0), "Main provider has not yet been selected");
        request.verifiers = new address[](0);
        request.chosenVerifiers = new address[](0);
        request.state = RequestStates.CHOOSING_VERIFIERS;

        request.majorityVoteHash = bytes32(0);
        request.majorityCount = 0;
        request.existMajority = true;
        request.roundIndex += 1;

        emit RoundInitialised(requestId);
        emit RoundStartedForVerificationSelection(requestId, request.layerComputeIndex);
    }

    // Function for verifiers to apply for verification
    function applyForVerificationForRequest(uint256 requestId) external {
        Request storage request = requests[requestId];
        require(request.hasBeenComputed, "Request not yet computed");
        require(msg.sender != request.mainProvider, "The main provider cannot apply to become a verifier");
        require(request.verifiers.length < request.numVerifiers, "Verifier limit reached");
        require(request.state == RequestStates.CHOOSING_VERIFIERS, "Verifier cannot apply for verification. Request state must be in choosing verifiers state");

        uint256 allowance = compToken.allowance(msg.sender, address(this));
        uint256 balance = compToken.balanceOf(msg.sender);
        require(allowance >= request.paymentPerRoundForVerifiers, "Insufficient stake");
        require(balance >= request.paymentPerRoundForVerifiers, "Insufficient stake");
        require(compToken.transferFrom(msg.sender, address(this), request.paymentPerRoundForVerifiers), "Insufficient stake");


        if(request.verificationDeadline <= block.timestamp + (3 * request.timeAllocatedForVerification)) {
            verificationDeadlinePassedForVeryfying(requestId);
            return;
        }
        require(!isVerifierApplied(requestId, msg.sender), "Verifier already applied");

        request.verifiers.push(msg.sender);
        emit VerificationApplied(requestId, msg.sender, request.layerComputeIndex);

        if (request.verifiers.length == request.numVerifiers) {
            chooseVerifiersForRequest(requestId);
        }
    }

    // function called when verification deadline has passed and we do not have enough verifiers for the round to start
    function verificationDeadlinePassedForVeryfying(uint256 requestId) public {
        Request storage request = requests[requestId];
        require(request.verificationDeadline < block.timestamp + (3 * request.timeAllocatedForVerification), "Verification deadline has not yet passed");
        require(request.state == RequestStates.CHOOSING_VERIFIERS, "Request must be in choosing verifiers state");
        for(uint i=0; i<request.verifiers.length; i++) {
            address verifier = request.verifiers[request.verifiers.length - 1];
            request.verifiers.pop();
            compToken.transfer(verifier, request.paymentPerRoundForVerifiers);
        }
        providerSuccess(requestId);
    }

    // Helper function to check if a verifier has already applied
    function isVerifierApplied(uint256 requestId, address verifier) internal view returns (bool) {
        Request storage request = requests[requestId];
        for (uint256 i = 0; i < request.verifiers.length; i++) {
            if (request.verifiers[i] == verifier) {
                return true;
            }
        }
        return false;
    }

   function chooseVerifiersForRequest(uint256 requestId) internal {
        Request storage request = requests[requestId];
        require(request.hasBeenComputed, "Request has not been computed yet");
        require(request.verifiers.length >= request.numVerifiersSampleSize, "Not enough verifiers to choose from");
        if (request.verificationDeadline < block.timestamp + (3 * request.timeAllocatedForVerification)) {
            verificationDeadlinePassedForVeryfying(requestId);
            return;
        }

        uint256 numUnchosen = request.verifiers.length - request.numVerifiersSampleSize;
        uint256[] memory randomNumbers = getRandomNumbers(request.verifiers.length, numUnchosen);

        // Select verifiers who will not be chosen and move them to the end
        for (uint256 i = 0; i < numUnchosen; i++) {
            uint256 randUnchosen = randomNumbers[i] % (request.verifiers.length - i);
            address unchosenVerifier = request.verifiers[randUnchosen];

            // Swap the unchosen verifier with the last verifier in the array
            request.verifiers[randUnchosen] = request.verifiers[request.verifiers.length - 1 - i];
            request.verifiers[request.verifiers.length - 1 - i] = unchosenVerifier;

            // Return stake to the unchosen verifier
            compToken.transfer(unchosenVerifier, request.paymentPerRoundForVerifiers);
        }

        // The remaining verifiers at the beginning of the list are the chosen verifiers
        for (uint256 i = 0; i < request.numVerifiersSampleSize; i++) {
            address chosenVerifier = request.verifiers[i];
            request.chosenVerifiers.push(chosenVerifier);
            emit VerifierChosen(requestId, chosenVerifier, request.layerComputeIndex);
        }

        startRound(requestId);
    }

    // Function to start a round of verification
    function startRound(uint256 requestId) internal {
        Request storage request = requests[requestId];
        require(request.layerComputeIndex < request.layerCount, "All layers have been processed");
        require(request.verificationDeadline > block.timestamp + (3 * request.timeAllocatedForVerification), "Verification Deadline has passed to start a round");

        request.verificationStartTime = block.timestamp;
        request.commitEndTime = block.timestamp + request.timeAllocatedForVerification;
        request.providerRevealEndTime = request.commitEndTime + request.timeAllocatedForVerification;
        request.commitmentRevealEndTime = request.providerRevealEndTime + request.timeAllocatedForVerification;

        emit CommitmentPhaseStarted(requestId, block.timestamp, request.commitEndTime, request.layerComputeIndex);
        request.state = RequestStates.COMMITMENT_STATE;
    }


    // Function to submit a commitment by a verifier
    function submitCommitment(
        uint256 requestId,
        bytes32 computedHash
    ) external {
        Request storage request = requests[requestId];
        require(request.state == RequestStates.COMMITMENT_STATE, "Request not yet in commitment state");
        require(block.timestamp <= request.commitEndTime, "Commitment phase ended");
        require(isVerifierChosen(requestId, msg.sender), "You are not a chosen verifier");

        Verification storage verification = verifications[requestId][msg.sender];
        verification.computedHash = computedHash;
        verification.revealed = false; // we set it to false, since we might come back to this again for a different round

        emit CommitmentSubmitted(requestId, msg.sender);
    }

    // Helper function to check if a verifier is chosen
    function isVerifierChosen(uint256 requestId, address verifier) internal view returns (bool) {
        Request storage request = requests[requestId];
        for (uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            if (request.chosenVerifiers[i] == verifier) {
                return true;
            }
        }
        return false;
    }

    // Function to reveal the provider's private key and hash of the answer
    // The answer hash is equal to: keccak256(abi.encode(agree, answer)), where agree is true
    function revealProviderKeyAndHash(
        uint256 requestId,
        bytes32 privateKey,
        bytes32 answerHash
    ) external {
        Request storage request = requests[requestId];
        require(msg.sender == request.mainProvider, "Only the main provider can reveal the key and hash");
        require(block.timestamp > request.commitEndTime, "Commitment phase not ended");
        require(block.timestamp <= request.providerRevealEndTime, "Provider reveal phase ended");
        request.mainProviderAnswerHash = keccak256(abi.encode(answerHash, true));

        request.state = RequestStates.PROVIDER_REVEAL_STATE;
        emit ProviderRevealed(requestId, privateKey, answerHash);
    }

    function revealCommitment(
        uint256 requestId,
        bool agree,
        bytes32 answer,
        bytes32 nonce
    ) external {
        Request storage request = requests[requestId];
        require(block.timestamp > request.providerRevealEndTime, "Provider reveal phase not ended");
        require(block.timestamp <= request.commitmentRevealEndTime, "Reveal phase ended");
        require(isVerifierChosen(requestId, msg.sender), "You are not a chosen verifier");

        Verification storage verification = verifications[requestId][msg.sender];
        require(!verification.revealed, "Commitment already revealed");
        require(keccak256(abi.encode(answer, nonce, msg.sender)) == verification.computedHash, "Invalid reveal values");

        verification.agree = agree;
        verification.answer = answer;
        verification.nonce = nonce;
        verification.revealed = true;
        verification.verifier = msg.sender;

        bytes32 voteHash = keccak256(abi.encode(verification.answer, verification.agree));
        votes[requestId][voteHash][request.roundIndex]++;
        voteAddresses[requestId][voteHash][request.roundIndex].push(verification.verifier);

        if (votes[requestId][voteHash][request.roundIndex] == request.majorityCount) {
            request.existMajority = false;
        } else if (votes[requestId][voteHash][request.roundIndex] > request.majorityCount) {
            request.existMajority = true;
            request.majorityCount = votes[requestId][voteHash][request.roundIndex];
            request.majorityVoteHash = voteHash;
        }

        request.state = RequestStates.COMMITMENT_REVEAL_STATE;
        emit RevealVerificationDetails(requestId, block.timestamp, msg.sender);
    }

    // Function to calculate the majority vote and distribute rewards
    function calculateMajorityAndReward(uint256 requestId) public {
        Request storage request = requests[requestId];

        require(block.timestamp >= request.commitmentRevealEndTime, "commitment stage has not yet completed");
        require(request.state == RequestStates.COMMITMENT_REVEAL_STATE, "Request not in correct state for calculating rewards");

        
        if (request.existMajority) {
            bool success = distributeRewardsAndStakes(requestId, request.majorityVoteHash);
            finalizeVerification(requestId, success);
        } else {
            handleNoMajority(requestId);
        }
    }

    // Function to handle the case when a majority cannot be determined
    function handleNoMajority(uint256 requestId) internal {
        Request storage request = requests[requestId];
        for (uint256 i = 0; i < request.chosenVerifiers.length; i++) {
            compToken.transfer(request.chosenVerifiers[i], request.paymentPerRoundForVerifiers);
        }
        emit NoMajorityForRound(requestId, request.layerComputeIndex);
        initialiseRound(requestId);
    }


    // Function to distribute rewards and penalties after the majority calculation
    // Verifiers are only paid if there is a majority
    function distributeRewardsAndStakes(uint256 requestId, bytes32 majorityVoteHash) internal returns(bool) {
        Request storage request = requests[requestId];
        address[] storage majorityVoters = voteAddresses[requestId][majorityVoteHash][request.roundIndex];
        uint256 reward = request.paymentPerRoundForVerifiers * request.numVerifiersSampleSize / majorityVoters.length;
        uint256 stake = request.paymentPerRoundForVerifiers;

        for (uint256 i = 0; i < majorityVoters.length; i++) {
            request.totalPaidForVerification += reward;
            compToken.transfer(majorityVoters[i], reward + stake);
        }
        return majorityVoteHash == request.mainProviderAnswerHash;
    }

    // Function to finalize the verification and compute the next layer
    function finalizeVerification(uint256 requestId, bool success) internal {
        Request storage request = requests[requestId];
        require(request.layerComputeIndex < request.layerCount, "All layers have been processed");

        if (success) {
          if (request.layerComputeIndex < request.layerCount - 1) {
            request.layerComputeIndex++;
            initialiseRound(requestId);
          } else {
            request.layerComputeIndex++;
            providerSuccess(requestId);
          }
        } else {
            providerFailure(requestId);
        }
    }

    function providerSuccess(uint256 requestId) internal {
        Request storage request = requests[requestId];
        request.completed = true;
        compToken.transfer(request.mainProvider, request.stake + request.paymentForProvider);
        request.state = RequestStates.SUCCESS;
        emit ProviderResultSuccessfullyVerified(requestId);
    }

    function providerEarlySuccessCall(uint256 requestId) public {
        Request storage request = requests[requestId];
        require(block.timestamp >= request.verificationDeadline && request.completed && request.state != RequestStates.UNSUCCESSFUL && !request.completed);
        request.completed = true;
        compToken.transfer(request.mainProvider, request.stake + request.paymentForProvider);
        request.state = RequestStates.SUCCESS;
        emit ProviderResultSuccessfullyVerified(requestId);
    }

    // Consumer gets to take the stake of the provider, if the provider did an incorrect calculation
    function providerFailure(uint256 requestId) internal {
        Request storage request = requests[requestId];
        compToken.transfer(request.consumer, request.paymentForProvider + request.stake + request.totalPaymentForVerifiers - request.totalPaidForVerification);
        request.completed = true;
        request.state = RequestStates.UNSUCCESSFUL;
        emit ProviderResultUnsuccessful(requestId);
    }

}
