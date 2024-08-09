// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/ComputationMarket.sol";
import "../contracts/COMPToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ComputationMarketTestMultipleRequests is Test {
    ComputationMarket public market;
    COMPToken public compToken;
    CompNFT public compNFT;
    HandlerFunctionsCompMarket public handler;
    mapping(address => uint256) consumerPayments;
    mapping(address => uint256) providerRewards;
    mapping(address => uint256) verifierPayments;


    address consumer1 = address(100);
    address consumer2 = address(101);
    address consumer3 = address(102);
    address provider1 = address(200);
    address provider2 = address(201);

    address[] public verifiers = [
        address(1),
        address(2),
        address(3),
        address(4),
        address(5),
        address(6),
        address(7),
        address(8),
        address(9),
        address(10),
        address(11)
    ];

    uint256 constant PROVIDER_STAKE_PERCENTAGE = 25;

    struct RequestParameters {
        address consumer;
        address provider;
        uint256 paymentForProvider;
        uint256 paymentPerRoundForVerifiers;
        uint256 numOperations;
        uint256 numVerifiers;
        uint256 computationDeadline;
        uint256 verificationDeadline;
        uint256 timeAllocatedForVerification;
        uint256 numVerifiersSampleSize;
    }

    RequestParameters[] public requestParams;

    struct RequestDetails {
        address consumer;
        uint256 paymentForProvider;
        uint256 totalPaymentForVerifiers;
        uint256 numOperations;
        uint256 numVerifiers;
        string operationFileURL;
        uint256 computationDeadline;
        uint256 verificationDeadline;
        uint256 totalPayment;
        bool completed;
        bool hasBeenComputed;
        uint256 numVerifiersSampleSize;
        address mainProvider;
        uint256 timeAllocatedForVerification;
        uint256 layerCount;
        uint256 layerComputeIndex;
        uint256 roundIndex;
        ComputationMarket.RequestStates state;
        uint256 stake;
        uint256 paymentPerRoundForVerifiers;
        uint256 totalPaidForVerification;
        uint256 protocolVersion;
        uint256 verifierSelectionCount;
        uint256 firstinitialisedTime;
        uint256 layerSize;
        bytes32 hashOfInputFiles;
    }

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

    function setUp() public {
        // Deploy the mock COMP token and the market contract
        compToken = new COMPToken(100000000000000);
        compNFT = new CompNFT();
        handler = new HandlerFunctionsCompMarket();
        market = new ComputationMarket(address(compToken), address(compNFT), address(handler));
        compNFT.transferNFTContractOwnership(address(market));

        // Initialize request parameters
        initializeRequestParams();

        // Distribute COMP tokens to test accounts
        distributeTokens();

        // Label accounts for better readability in logs
        labelAccounts();
    }

    function initializeRequestParams() internal {
        requestParams.push(RequestParameters(consumer1, provider1, 100, 10, 3000, 7, 10 days, 20 days, 1 hours, 5));
        requestParams.push(RequestParameters(consumer2, provider2, 200, 20, 6000, 5, 20 days, 30 days, 2 hours, 4));
        requestParams.push(RequestParameters(consumer3, provider1, 150, 15, 4500, 6, 15 days, 250 days, 1.5 hours, 5));
        requestParams.push(RequestParameters(consumer2, provider2, 150, 12, 3200, 8, 12 days, 220 days, 1.2 hours, 6));
        requestParams.push(RequestParameters(consumer1, provider1, 300, 18, 5200, 9, 18 days, 280 days, 1.8 hours, 7));
    }

    function distributeTokens() internal {
        compToken.transfer(provider1, 2000);
        compToken.transfer(provider2, 2000);
        compToken.transfer(consumer1, 100000);
        compToken.transfer(consumer2, 100000);
        compToken.transfer(consumer3, 100000);
        for (uint256 i = 0; i < verifiers.length; i++) {
            compToken.transfer(verifiers[i], 100);
        }
    }

    function labelAccounts() internal {
        vm.label(consumer1, "Consumer1");
        vm.label(consumer2, "Consumer2");
        vm.label(consumer3, "Consumer3");
        vm.label(provider1, "Provider1");
        vm.label(provider2, "Provider2");
        for (uint256 i = 0; i < verifiers.length; i++) {
            vm.label(verifiers[i], string(abi.encodePacked("Verifier", i + 1)));
        }
    }

    function approveTokens(address user, uint256 amount) internal {
        vm.startPrank(user);
        compToken.approve(address(market), amount);
        vm.stopPrank();
    }

    function createRequest(uint256 requestIndex) internal {
        RequestParameters memory params = requestParams[requestIndex];
        vm.startPrank(params.consumer);
        uint256 totalPayment = params.paymentForProvider + params.paymentPerRoundForVerifiers * params.numVerifiersSampleSize * ((params.numOperations + 999) / 1000);
        compToken.approve(address(market), totalPayment);
        string[] memory inputFileURLs = new string[](1);
        inputFileURLs[0] = "input_file_url";
        market.createRequest(
            params.paymentForProvider,
            params.paymentPerRoundForVerifiers,
            params.numOperations,
            params.numVerifiers,
            inputFileURLs,
            "operation_file_url",
            block.timestamp + params.computationDeadline,
            block.timestamp + params.verificationDeadline,
            params.timeAllocatedForVerification,
            params.numVerifiersSampleSize,
            1,
            1000,
            bytes32(0),
            params.paymentForProvider * PROVIDER_STAKE_PERCENTAGE / 100
        );
        vm.stopPrank();
    }

    function selectRequest(uint256 requestId, address providerAddr, uint256 paymentForProvider) internal {
        vm.startPrank(providerAddr);
        uint256 stakeAmount = (paymentForProvider * PROVIDER_STAKE_PERCENTAGE) / 100;
        compToken.approve(address(market), stakeAmount);
        market.selectRequest(requestId);
        vm.stopPrank();
    }

    function completeRequest(uint256 requestId, address providerAddr) internal {
        string[] memory outputFileURLs = new string[](1);
        outputFileURLs[0] = "output_file_url";

        vm.startPrank(providerAddr);
        market.completeRequest(requestId, outputFileURLs);
        vm.warp(block.timestamp + 6);
        vm.stopPrank();
    }

    function applyForVerification(address verifierAddress, uint256 requestId, uint256 paymentPerRoundForVerifiers) internal {
        approveTokens(verifierAddress, paymentPerRoundForVerifiers);
        vm.startPrank(verifierAddress);
        market.applyForVerificationForRequest(requestId);
        vm.stopPrank();
        vm.warp(block.timestamp + 6);
    }

    function triggerVerification(address verifierAddress, uint256 requestId) internal {
        vm.startPrank(verifierAddress);
        market.chooseVerifiersForRequestTrigger(requestId);
        vm.stopPrank();
    }

    function submitCommitment(address verifierAddress, uint256 requestId, bytes32 computedHash) internal {
        vm.startPrank(verifierAddress);
        market.submitCommitment(requestId, computedHash);
        vm.stopPrank();
    }

    function revealProviderKeyAndHash(uint256 requestId, address providerAddr, bytes32 privateKey, bytes32 answerHash) internal {
        vm.startPrank(providerAddr);
        uint256 initialisationVector = block.timestamp;
        market.revealProviderKeyAndHash(requestId, uint256(keccak256(abi.encodePacked(privateKey, bytes32(block.timestamp)))), initialisationVector, answerHash);
        vm.stopPrank();
    }

    function collectRewards(address verifierAddress, uint256 requestId, uint256 roundNum) internal {
        vm.startPrank(verifierAddress);
        market.calculateMajorityAndReward(requestId, roundNum);
        vm.stopPrank();
    }
    function performRound(
    uint256 requestId,
    address[] memory verifiersForRound,
    bytes32 answer,
    uint256 roundNum
) internal {
    // Apply for verification
    for (uint256 i = 0; i < verifiersForRound.length; i++) {
        applyForVerification(verifiersForRound[i], requestId, requestParams[requestId].paymentPerRoundForVerifiers);
    }

    // Trigger verification
    for (uint256 i = 0; i < verifiersForRound.length; i++) {
        triggerVerification(verifiersForRound[i], requestId);
    }

    // Fetch the chosen verifiers from the request structure
    address[] memory chosenVerifiers = getVerifiersChosen(requestId, roundNum);

    for (uint256 i = 0; i < chosenVerifiers.length; i++) {
        uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i]);
        bytes32 computedHash = keccak256(abi.encodePacked(answer, keccak256(abi.encodePacked("nonce", verifierIndex)), chosenVerifiers[i]));
        submitCommitment(chosenVerifiers[i], requestId, computedHash);
    }

    vm.warp(block.timestamp + requestParams[requestId].timeAllocatedForVerification + 1);

    bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
    bytes32 answerHash = answer;
    revealProviderKeyAndHash(requestId, requestParams[requestId].provider, privateKey, answerHash);

    vm.warp(block.timestamp + requestParams[requestId].timeAllocatedForVerification + 1);

    for (uint256 i = 0; i < chosenVerifiers.length; i++) {
        uint256 verifierIndex = findVerifierIndex(chosenVerifiers[i]);
        vm.startPrank(chosenVerifiers[i]);
        market.revealCommitment(requestId, true, answer, keccak256(abi.encodePacked("nonce", verifierIndex)));
        vm.stopPrank();
    }

    vm.warp(block.timestamp + requestParams[requestId].timeAllocatedForVerification + 1);

    for (uint256 i = 0; i < chosenVerifiers.length; i++) {
        collectRewards(chosenVerifiers[i], requestId, roundNum);
    }
    }

    function getVerifiersChosen(uint256 requestId, uint256 roundNum) internal view returns (address[] memory) {
        address[] memory chosenVerifiers = new address[](requestParams[requestId].numVerifiersSampleSize);
        uint256 k = 0;

        for (uint256 i = 0; i < verifiers.length; i++) {
            if (market.isVerifierChosenForRound(requestId, roundNum, verifiers[i])) {
                chosenVerifiers[k] = verifiers[i];
                k++;
            }
        }
        return chosenVerifiers;
    }

    function findVerifierIndex(address verifier) internal view returns (uint256) {
        for (uint256 i = 0; i < verifiers.length; i++) {
            if (verifiers[i] == verifier) {
                return i;
            }
        }
        revert("Verifier not found");
    }

    function checkFinalBalances() internal {
        // Mapping to store total payments and rewards for each consumer, provider, and verifier

        // Calculate total payments and rewards
        for (uint256 i = 0; i < requestParams.length; i++) {
            RequestParameters memory params = requestParams[i];
            uint256 totalPayment = params.paymentForProvider + params.paymentPerRoundForVerifiers * params.numVerifiersSampleSize * ((params.numOperations + 999) / 1000);
            consumerPayments[params.consumer] += totalPayment;
            providerRewards[params.provider] += params.paymentForProvider;
        }


        // get chosen verifiers for each request
        for (uint256 i = 0; i < requestParams.length; i++) {
            RequestParameters memory params = requestParams[i];
            for(uint256 j=1; j<(params.numOperations+999)/1000 + 1; j++) {
                address[] memory chosenVerifiers = getVerifiersChosen(i, j);
                for(uint256 k=0; k<chosenVerifiers.length; k++) {
                    verifierPayments[chosenVerifiers[k]] += params.paymentPerRoundForVerifiers;
                }
            }
        }

        // Check balances for verifiers
        for (uint256 i = 0; i < verifiers.length; i++) {
            address verifierAddr = verifiers[i];
            uint256 expectedVerifierBalance = 100 + verifierPayments[verifierAddr];
            assertEq(compToken.balanceOf(verifierAddr), expectedVerifierBalance, "Verifier balance is incorrect");
        }

        // Check balances for providers
        for (uint256 i = 0; i < requestParams.length; i++) {
            address providerAddr = requestParams[i].provider;
            uint256 expectedProviderBalance = 2000 + providerRewards[providerAddr];
            assertEq(compToken.balanceOf(providerAddr), expectedProviderBalance, "Provider balance is incorrect");
        }


        // Check balances for consumers
        for (uint256 i = 0; i < requestParams.length; i++) {
            address consumerAddr = requestParams[i].consumer;
            uint256 expectedConsumerBalance = 100000 - consumerPayments[consumerAddr];
            assertEq(compToken.balanceOf(consumerAddr), expectedConsumerBalance, "Consumer balance is incorrect");
        }
    }

    function testMultipleRequests() public {
        // Create requests
        for (uint256 i = 0; i < requestParams.length; i++) {
            createRequest(i);
        }

        // Select requests
        for (uint256 i = 0; i < requestParams.length; i++) {
            selectRequest(i, requestParams[i].provider, requestParams[i].paymentForProvider);
            completeRequest(i, requestParams[i].provider);
        }

        // Perform rounds for each request and complete requests
        for (uint256 i = 0; i < requestParams.length; i++) {
            uint256 rounds = (requestParams[i].numOperations + 999) / 1000;
            bytes32 answer = keccak256(abi.encodePacked("answer"));
            uint256 k = requestParams[i].numVerifiers;
            address[] memory verifiersRound = new address[](k);
            for (uint256 j = 0; j < k; j++) {
                verifiersRound[j] = verifiers[j];
            }
            for(uint256 h=0; h<verifiers.length; h++) {
            }
            for (uint256 round = 1; round <= rounds; round++) {
                performRound(i, verifiersRound, answer, round);
                for(uint256 h=0; h<verifiers.length; h++) {
                }
            }
        }

        // Check final balances
        checkFinalBalances();
    }
}




