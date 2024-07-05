/*// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/ComputationMarket.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestComputationMarketInTT {
    IERC20 public compToken;
    ComputationMarket public market;
    uint256 public initialBalance = 1 ether;

    function beforeAll() public {
        compToken = IERC20(DeployedAddresses.COMPToken());
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
        uint256 computationDeadline = block.timestamp + 1 ;
        uint256 verificationDeadline = block.timestamp + 20 ;
        uint256 timeAllocatedForVerification = 1 ;

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

        //ComputationMarket.Request memory request = market.requests(0);
        //Assert.equal(request.consumer, address(this), "Consumer address should be correct");
        //Assert.equal(request.paymentForProvider, paymentForProvider, "Payment for provider should be correct");
        //Assert.equal(request.numVerifiers, numVerifiers, "Number of verifiers should be correct");
    }
}*/