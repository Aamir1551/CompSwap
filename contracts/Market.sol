// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./CompToken.sol";

contract Market {

    struct Order {
        string data; // this could be a pointer on some dectralised storage solution
        uint256 id;
        bool isCompleted;
        uint256 price;
        address from;
        uint256 numOperations;
    }

    struct Solution {
        string data; // This is the solution
        uint256 id; // relates it to the id of the order
        address from; // who solved the problem
    }

    struct StockMarketOrder {
        string data; // this could be a pointer on some dectralised storage solution
        uint256 id;
        bool isCompleted;
        uint256 price;
        address from;
        uint256 numOperations; // this should just be a 1000
    }

    uint256 orderCount;

    CompToken ct;
    mapping(uint256 => Order) public marketPlace;
    mapping(uint256 => Order) public stockMarket;
    mapping(uint256 => Solutions) public solutions;

    constructor(CompToken _ct) {
        ct = _ct;
    }

    modifier isNotComplete(uint256 orderId) {
        require(!marketPlace[uint256].isCompleted, "Solution has already been solved");
    }

    // move money from the user who created the order to the contarct
    // create the order
    // update the order count by 1
    function submitOrder(string memory _data, uint256 _price, uint256 _numOperations) public {
        marketPlace[orderCount] = Order(_data, orderCount, False, _price, msg.sender, _numOperations);
        orderCount += 1;
    }

    // 1. mark the order as completed
    // 2. store the solution in the solution map --> this is not requried in the decentralised storage solution, since the
    // data will be stored there anyways!
    function completeOrder(uint256 orderId, string memory data) isNotComplete(orderId) public {
        marketPlace[orderId].isCompleted = True;


    }

    // data will later be stored on a decentralised storage solution. The solutions that the providers publish, will be
    // published to the decentralised storage solution itself, and the market contract will just verify that it is correct
    function pushCheckPointsToStorage(string memory data, uint orderID) public {

    }

    
    /* The way the verification service will work is that the sender will give the id of the orginal order, and 
    then an index into it, and this is what the provider will try to solve.
    */
    
    // 1. Create the order, and add it to the hashmap
    // 2. Attach a price that the user is willing to pay for verification
    // 3. 
    
    function addToStockMarket(uint orderId) public {
        
    }

    function verifyStockMarketOrder(string memory data) public {

    }

    function solveIncorrectAnswer(string memory data) public {

    }

}