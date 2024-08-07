// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract HandlerFunctionsCompMarket {

    function defaultVerifierVoteCounts(address add) external pure returns (uint256) {
        return add != address(0) ? 1 : 0;
    }

    function getRandomNumber(uint256 maxLimit) public view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % maxLimit;
    }

}