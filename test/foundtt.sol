// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/ComputationMarket.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock COMP Token", "COMP") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
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

    function setUp() public {
        // Deploy the mock COMP token and the market contract
        compToken = new MockERC20();
        market = new ComputationMarket(address(compToken));

        // Distribute COMP tokens to test accounts
        compToken.transfer(consumer, 10000 * 10 ** compToken.decimals());
        compToken.transfer(provider, 10000 * 10 ** compToken.decimals());
        compToken.transfer(verifier1, 10000 * 10 ** compToken.decimals());
        compToken.transfer(verifier2, 10000 * 10 ** compToken.decimals());
        compToken.transfer(verifier3, 10000 * 10 ** compToken.decimals());

        // Label accounts for better readability in logs
        vm.label(consumer, "Consumer");
        vm.label(provider, "Provider");
        vm.label(verifier1, "Verifier1");
        vm.label(verifier2, "Verifier2");
        vm.label(verifier3, "Verifier3");
    }

    function testCreateRequest() public {
        vm.startPrank(consumer);
        compToken.approve(address(market), 1500 * 10 ** compToken.decimals());
        string[] memory inputFileURLs = new string[](1);
        inputFileURLs[0] = "input_file_url";
        market.createRequest(
            1000 * 10 ** compToken.decimals(),
            500 * 10 ** compToken.decimals(),
            3000,
            3,
            inputFileURLs,
            "operation_file_url",
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            1 hours
        );
        vm.stopPrank();

        ComputationMarket.Request memory request = market.requests(0);
        assertEq(request.consumer, consumer);
        assertEq(request.paymentForProvider, 1000 * 10 ** compToken.decimals());
        assertEq(request.numVerifiers, 3);
    }

    function testSelectRequest() public {
        testCreateRequest(); // Ensure a request is created

        vm.startPrank(provider);
        compToken.approve(address(market), 100 * 10 ** compToken.decimals());
        market.selectRequest(0);
        vm.stopPrank();

        ComputationMarket.Request memory request = market.requests(0);
        assertEq(request.mainProvider, provider);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.PROVIDER_SELECTED_NOT_COMPUTED));
    }

    function testCancelRequest() public {
        testCreateRequest(); // Ensure a request is created

        vm.startPrank(consumer);
        market.cancelRequest(0);
        vm.stopPrank();

        ComputationMarket.Request memory request = market.requests(0);
        assertTrue(request.completed);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CANCELLED));
    }

    function testCompleteRequest() public {
        testSelectRequest(); // Ensure a request is selected

        vm.startPrank(provider);
        string[] memory outputFileURLs = new string[](1);
        outputFileURLs[0] = "output_file_url";
        market.completeRequest(0, outputFileURLs);
        vm.stopPrank();

        ComputationMarket.Request memory request = market.requests(0);
        assertTrue(request.hasBeenComputed);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.CHOOSING_VERIFIERS));
    }

    function testApplyForVerificationForRequest() public {
        testCompleteRequest(); // Ensure a request is completed

        vm.startPrank(verifier1);
        compToken.approve(address(market), 50 * 10 ** compToken.decimals());
        market.applyForVerificationForRequest(0);
        vm.stopPrank();

        ComputationMarket.Request memory request = market.requests(0);
        assertEq(request.verifiers.length, 1);
    }

    function testSubmitCommitment() public {
        testApplyForVerificationForRequest(); // Ensure a verifier applied

        vm.startPrank(verifier1);
        bytes32 computedHash = keccak256(abi.encodePacked("commitment"));
        market.submitCommitment(0, computedHash);
        vm.stopPrank();

        ComputationMarket.Verification memory verification = market.verifications(0, verifier1);
        assertEq(verification.computedHash, computedHash);
        assertFalse(verification.revealed);
    }

    function testRevealProviderKeyAndHash() public {
        testSubmitCommitment(); // Ensure a commitment is submitted

        vm.startPrank(provider);
        bytes32 privateKey = keccak256(abi.encodePacked("private_key"));
        bytes32 answerHash = keccak256(abi.encodePacked("answer_hash"));
        market.revealProviderKeyAndHash(0, privateKey, answerHash);
        vm.stopPrank();

        ComputationMarket.Request memory request = market.requests(0);
        assertEq(request.mainProviderAnswerHash, answerHash);
        assertEq(uint256(request.state), uint256(ComputationMarket.RequestStates.PROVIDER_REVEAL_STATE));
    }

    function testRevealCommitment() public {
        testRevealProviderKeyAndHash(); // Ensure provider reveals their key and hash

        vm.startPrank(verifier1);
        bool agree = true;
        bytes32 answer = keccak256(abi.encodePacked("answer"));
        bytes32 nonce = keccak256(abi.encodePacked("nonce"));
        market.revealCommitment(0, agree, answer, nonce);
        vm.stopPrank();

        ComputationMarket.Verification memory verification = market.verifications(0, verifier1);
        assertTrue(verification.revealed);
    }

    function testCalculateMajorityAndReward() public {
        testRevealCommitment(); // Ensure verifier reveals their commitment

        market.calculateMajorityAndReward(0);
        ComputationMarket.Request memory request = market.requests(0);
        // Add more asserts to check the state and balances of verifiers and provider
    }
}