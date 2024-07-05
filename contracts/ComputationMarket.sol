// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ComputationMarket {

    IERC20 public compToken;

    struct Request {
        address consumer;
        uint256 paymentForProvider;
        uint256 paymentForVerifiers;
        uint256 numOperations;
        uint256 numVerifiers;
        string[] inputFileURLs;
        string operationFileURL;
        uint256 computationDeadline;
        uint256 verificationDeadline;
        uint256 totalPayment;
        bool completed;
        bytes32 publicKey;
        bool hasBeenComputed;
        int numVerifiersSampleSize;
        address[] verifiers;
        address[] chosenVerifiers;
        address mainProvider;
        uint256 timeAllocatedForVerification;
        uint256 layers;
        uint256 layerComputeIndex;
    }

    struct Verification {
        address verifier;
        uint256 round;
        bool agree;
        uint256 answer;
        bytes32 nonce;
        bool revealed;
        bytes32 hashComputed;
    }

    struct roundInfo {
      uint256 roundNum;
      uint256 numberOfVerifications;
      uint256 numberOfCommiters;
      bool revealStarted;
    }

    mapping(uint256 => Request) public requests;
    mapping(uint256 => address) public requestProviders;

    // parameters: requestProvidersId, round, address of verifier
    mapping(uint256 => mapping(uint256 => mapping(address => Verification))) public verifications;
    mapping(uint256 => roundInfo) public roundsInfo; // a mapping from the ticketId to the round num we are on for it

    uint256 public requestCount;
    uint256 public constant PROVIDER_STAKE_PERCENTAGE = 10; // 10%
    uint256 public constant MIN_VERIFIERS = 3;

    event RequestCreated(uint256 indexed requestId, address indexed consumer);
    event ProviderSelected(uint256 indexed requestId, address indexed provider);
    event CommitmentSubmitted(uint256 indexed requestId, address indexed provider, uint256 indexed round);
    event ResultVerified(uint256 indexed requestId, uint256 indexed round, bool success);

    constructor(address compTokenAddress) {
      compToken = IERC20(compTokenAddress);
    }

    function createRequest(
        address consumer,
        uint256 paymentForProvider,
        uint256 paymentForVerifiers,
        uint256 numOperations,
        uint256 numVerifiers,
        string[] memory inputFileURLs,
        string memory operationFileURL,
        uint256 computationDeadline,
        uint256 verificationDeadline,
        bool completed,
        bytes32 publicKey,
        uint256 timeAllocatedForVerification
    ) public payable {
        require(numVerifiers >= MIN_VERIFIERS, "At least 3 verifiers required");
        require(numVerifiers % 2 == 1, "Number of verifiers must be odd");
        uint256 totalPayment = paymentForProvider + paymentForVerifiers;
        require(compToken.transferFrom(msg.sender, address(this), totalPayment), "Payment failed");

        requestCount++;
        requests[requestCount] = Request({
            consumer: msg.sender,
            paymentForProvider: paymentForProvider,
            paymentForVerifiers: paymentForVerifiers,
            numOperations: numOperations,
            numVerifiers: numVerifiers,
            inputFileURLs: inputFileURLs,
            operationFileURL: operationFileURL,
            computationDeadline: block.timestamp + computationDeadline,
            verificationDeadline: block.timestamp + verificationDeadline,
            totalPayment: totalPayment,
            completed: false,
            publicKey: publicKey,
            hasBeenComputed: false,
            mainProvider: address(0),
            verifiers: [],
            listOfVerifiers: [],
            timeAllocatedForVerification: timeAllocatedForVerification,
            layers: (numOperations + 999) / 1000,
            layerComputeIndex : 0
        });

        emit RequestCreated(requestCount, msg.sender);
    }

    function selectRequest(uint256 requestId) public payable {
        Request storage request = requests[requestId];
        require(block.timestamp <= request.computationDeadline, "Computation deadline passed");
        require(requestProviders[requestId] == address(0), "Provider already selected");
        require(compToken.transferFrom(msg.sender, address(this), (request.paymentForProvider * PROVIDER_STAKE_PERCENTAGE / 100)), "Insufficient stake");

        requestProviders[requestId] = msg.sender;

        emit ProviderSelected(requestId, msg.sender);
    }

    function completeRequest(uint256 requestId) public {
        Request storage request = requests[requestId];
        require(block.timestamp <= request.computationDeadline, "Computation deadline passed");
        require(requestProviders[requestId] == msg.sender, "Only chosen provider can solve requst");
        request.hasBeenComputed = true;
    }

    function getRandomNumbers(uint256 maxLimit, uint256) private pure returns(uint256[])  {
    }

    
    // ensure to emit an evnt for all the chosen verifiers
    // we use random numbers to select a verifier, and we sample without replacement
    function chooseVerifiersForRequest(uint256 requestId) public {
      Request storage request = requests[requestId];
      uint256[] randomNumbers  = getRandomNumbers(100, request.numVerifiersSampleSize);
      for(int i = 0; i < request.numVerifiersSampleSize; i++) {
        uint256 randChosen = randomNumbers[i]%(request.verifiers.length - i);
        request.chosenVerifiers.push(request.verifiers[randChosen]);
        address t = request.verifiers[randChosen];
        request.verifiers[randChosen] = request.verifiers[request.verifiers.length - i];
        request.verifiers[request.verifiers.length - i] = t;
        emit chosenVerifier(requestId, request.verifiers[randChosen]);
      }
      this.startRound(requestId, 0);
    }

    function applyForVerificationForRequest(uint256 requestId) public {
      // they will all have to pay a certain amount of link tokens to make this possible
      Request storage request = requests[requestId];
      require(compToken.transferFrom(msg.sender, address(this), request.paymentForVerifiers / request.layers / request.numVerifiersSampleSize), "Insufficient Stake");
      require(request.hasBeenComputed == false, "Request still hasn't been computed");
      require(request.verifiers.length < request.numVerifiers, "Limit has been reached for number of verifiers for request with ID " + requestId);
      request.verifiers.push(msg.sender);
      if(request.verifiers.length == request.numVerifiers) {
        chooseVerifiersForRequest(requestId);
      }
    }

    function startRound(uint256 requestId, uint256 round) public {
      Request storage request = requests[requestId];
      roundsInfo[requestId] = roundInfo(round, 0, false, 0);
      for(int i=0; i<request.chosenVerifiers.length; i++) {
        verifications[requestId][round][request.chosenVerifiers[i]] = 1;
      }
    }

    // we need the below function for the verifiers to submit their commitments
    function submitCommitment(
      bytes32 computedHash,
      uint256 round,
      uint256 requestId
    ) public {
      Request storage request = requests[requestId];
      // ensure that the msg.sender is in the list of sample sized verifiers
      require(verifications[requestId][round][msg.sender] != 0, "You are not a selected commiter");
      if(verifications[requestId][round][msg.sender] != 1) {
        roundsInfo[round].numberOfVerifications += 1;
      }
      verifications[requestId][round][msg.sender].computedHash = computedHash;
      verifications[requestId][round][msg.sender].round = round;
      emit CommitmentSubmitted(requestId, msg.sender, round);
      if(roundsInfo[round].numberOfVerifiations == request.numVerifiersSampleSize) {
        emit RoundRevealStarted(requestId, round);
      }

    }

    // we need to apply this after all the verification nodes have sumitted their answers
    function revealCommitment(
        uint256 requestId,
        bool agree,
        uint256 answer,
        uint256 round,
        bytes32 nonce
    ) public {
        require(verifications[requestId][round][msg.sender] != 0, "You are not a selected commiter");
        require(roundsInfo[requestId][round].revealStarted, "The revealing stage still hasn't started");
        require(keccak256(abi.encode(agree, answer, round, nonce, msg.sender)) == verifications[requestId][round][msg.sender].computedHash, 
        "Values given does not match hash"
        );
        verifications[requestId][round][msg.sender].verifier = msg.sender;
        verifications[requestId][round][msg.sender].round = round;
        verifications[requestId][round][msg.sender].agree = agree;
        verifications[requestId][round][msg.sender].nonce = nonce;
        if(verifications[requestId][round][msg.sender] != 1) {
          roundsInfo[round].numberOfCommiters += 1;
        }
        if(roundsInfo[round].numberOfCommiters == requests[requestId].numVerifiersSampleSize) {
          calculateMajoriyAndReward(requestId, round);
        }
    }

    struct answersVoting {
      uint256 answer;
      bool agreed;
    }

    function calculateMajoriyAndReward(uint256 requestId, uint256 round) public {
      mapping(answersVoting => address[]) votes;
      Request request = requests[requestId];
      address[] userAddressesVotes = requests[requestId].chosenVerifiers;
      answersVoting maj = answersVoting(0, false);
      uint256 majCount = 0; 
      bool noMaj = false;
      for(int i=0; i<requests[requestId].numVerifiersSampleSize; i++) {
        uint256 a = verifications[requestId][round][userAddressesVotes[i]].answer;
        bool ag = verifications[requestId][round][userAddressesVotes[i]].agreed;
        address v = verifications[requestId][round][userAddressesVotes[i]].agreed;
        votes[answersVoting(a, ag)].push(v);
        uint256 l = answersVoting(a, ag).length;
        if(maj.answer == a && maj.agreed = ag) {
          majCount += 1;
        } else {
          if (l == majCount) {
            noMaj = true;
          } else {
            noMaj = false;
            maj.answer = a;
            maj.agreed = ag;
          }
        }
      }
      if(noMaj) {
        for(int i=0; i<request.chosenVerifiers.length; i++) {
          compToken.transfer(address(this), request.chosenVerifiers[i], request.paymentForVerifiers / request.layers / request.numVerifiersSampleSize);
        }
        // start the round again, but this time choose random verifiers all again
      } else {
        for(int i=0; i<votes[maj].length; i++) {
          compToken.transfer(address(this), votes[maj][i], request.paymentForVerifiers / request.layers / votes[maj].length + request.paymentForVerifiers / request.layers / request.numVerifiersSampleSize);
          if(maj.agreed) {
            // if there's a next round, start a next round
            // if there is no next round, then move onto the next 1000 operations
          }
        }
      }
    }
}