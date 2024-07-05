/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/ComputationMarket.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestComputationMarket {
    IERC20 public compToken;
    ComputationMarket public market;
    uint256 public initialBalance = 1 ether;

    function beforeAll() public {
        compToken = IERC20(DeployedAddresses.ERC20());
        market = ComputationMarket(DeployedAddresses.ComputationMarket());
    }

    function testCreateRequest() public {
        uint256 paymentForProvider = 1000;
        uint256 paymentForVerifiers = 500;
        uint256 numOperations = 3000;
        uint256 numVerifiers = 3;
        string[] memory inputFileURLs = new string[](1);
        inputFileURLs[0] = "input_file_url";
        string memory operationFileURL = "operation_file_url";
        uint256 computationDeadline = block.timestamp + 1 days;
        uint256 verificationDeadline = block.timestamp + 2 days;
        uint256 timeAllocatedForVerification = 1 hours;

        market.createRequest(
            paymentForProvider,
            paymentForVerifiers,
            numOperations,
            numVerifiers,
            inputFileURLs,
            operationFileURL,
            computationDeadline,
            verificationDeadline,
            timeAllocatedForVerification
        );

        ComputationMarket.Request memory request = market.requests(0);
        Assert.equal(request.consumer, address(this), "Consumer address should be correct");
        Assert.equal(request.paymentForProvider, paymentForProvider, "Payment for provider should be correct");
        Assert.equal(request.numVerifiers, numVerifiers, "Number of verifiers should be correct");
    }

    function testSelectRequest() public {
        uint256 requestId = 0;
        market.selectRequest(requestId);
        ComputationMarket.Request memory request = market.requests(requestId);
        Assert.equal(request.mainProvider, address(this), "Main provider should be correct");
        Assert.equal(request.state, ComputationMarket.RequestStates.PROVIDER_SELECTED_NOT_COMPUTED, "State should be PROVIDER_SELECTED_NOT_COMPUTED");
    }

    function testCancelRequest() public {
        uint256 requestId = 1;
        market.cancelRequest(requestId);
        ComputationMarket.Request memory request = market.requests(requestId);
        Assert.isTrue(request.completed, "Request should be marked as completed");
        Assert.equal(request.state, ComputationMarket.RequestStates.CANCELLED, "State should be CANCELLED");
    }

    function testCompleteRequest() public {
        uint256 requestId = 2;
        string[] memory outputFileURLs = new string[](1);
        outputFileURLs[0] = "output_file_url";
        market.completeRequest(requestId, outputFileURLs);
        ComputationMarket.Request memory request = market.requests(requestId);
        Assert.isTrue(request.hasBeenComputed, "Request should be marked as computed");
        Assert.equal(request.state, ComputationMarket.RequestStates.CHOOSING_VERIFIERS, "State should be CHOOSING_VERIFIERS");
    }

    function testApplyForVerificationForRequest() public {
        uint256 requestId = 3;
        market.applyForVerificationForRequest(requestId);
        ComputationMarket.Request memory request = market.requests(requestId);
        Assert.equal(request.verifiers.length, 1, "Verifier should be added to the list");
    }

    function testSubmitCommitment() public {
        uint256 requestId = 4;
        bytes32 computedHash = keccak256(abi.encodePacked("commitment"));
        market.submitCommitment(requestId, computedHash);
        ComputationMarket.Verification memory verification = market.verifications(requestId, address(this));
        Assert.equal(verification.computedHash, computedHash, "Computed hash should be stored");
        Assert.isFalse(verification.revealed, "Commitment should not be revealed yet");
    }

    function testRevealProviderKeyAndHash() public {
        uint256 requestId = 5;
        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("answer_hash"));
        market.revealProviderKeyAndHash(requestId, privateKey, answerHash);
        ComputationMarket.Request memory request = market.requests(requestId);
        Assert.equal(request.mainProviderAnswerHash, answerHash, "Answer hash should be stored");
        Assert.equal(request.state, ComputationMarket.RequestStates.PROVIDER_REVEAL_STATE, "State should be PROVIDER_REVEAL_STATE");
    }

    function testRevealCommitment() public {
        uint256 requestId = 6;
        bool agree = true;
        bytes32 answer = keccak256(abi.encodePacked("answer"));
        bytes32 nonce = keccak256(abi.encodePacked("nonce"));
        market.revealCommitment(requestId, agree, answer, nonce);
        ComputationMarket.Verification memory verification = market.verifications(requestId, address(this));
        Assert.isTrue(verification.revealed, "Commitment should be revealed");
    }

    function testCalculateMajorityAndReward() public {
        uint256 requestId = 7;
        market.calculateMajorityAndReward(requestId);
        ComputationMarket.Request memory request = market.requests(requestId);
        // Add more asserts to check the state and balances of verifiers and provider
    }
}
*/