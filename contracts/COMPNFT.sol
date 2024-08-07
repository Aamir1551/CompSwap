// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract CompNFT is ERC721, Ownable {
    uint256 public nextTokenId;

    struct CompNFT_Data {
        uint256 compNFT_id; // The ID of the NFT
        uint256 amountToPay; // Amount to be paid to the NFT Ower was request is verified
        uint256 requestID; // The ID of the request
        address originalProvider; // The original provider of the request
        bool hasBeenPaid;
    }

    // Mapping of request ID to NFT struct
    mapping(uint256 => CompNFT_Data) public providerNFTs;

    // Mapping of NFT ID to request ID
    mapping(uint256 => uint256) public NFTRequestID;

    // Mapping of number of requests successfully completed by provider
    mapping(address => uint256) public providerSuccessfulRequestCount;

    // Mapping of number of requests failed by provider
    mapping(address => uint256) public providerFailedRequestCount;

    // Mapping of number of requests picked up by provider
    mapping(address => uint256) public providerPickedUpRequestCount;

    constructor() ERC721("COMP_NFT", "CNFT") Ownable(msg.sender) {}

    function providerSuccess(uint256 requestId) external onlyOwner returns (address) {
        CompNFT_Data storage compNFTData = providerNFTs[requestId];
        providerSuccessfulRequestCount[compNFTData.originalProvider]++;
        compNFTData.hasBeenPaid = true;
        address toPay = this.ownerOf(compNFTData.compNFT_id);
        return toPay;
    }

    function providerFailure(uint256 requestId) external onlyOwner {
        CompNFT_Data storage compNFTData = providerNFTs[requestId];
        providerFailedRequestCount[compNFTData.originalProvider]++;
    }

    function mint(address to, uint256 paymentForProvider, uint256 requestId) external onlyOwner returns (uint256) {
        uint256 tokenId = nextTokenId;
        nextTokenId++;
        providerPickedUpRequestCount[to]++;
        providerNFTs[requestId] = CompNFT_Data(
            {
                compNFT_id: tokenId, 
                amountToPay: paymentForProvider,
                requestID: requestId, 
                originalProvider: to, 
                hasBeenPaid: false
            });
        NFTRequestID[tokenId] = requestId;
        _safeMint(to, tokenId);
        return tokenId;
    }

    function transferNFTContractOwnership(address newOwner) external onlyOwner {
        transferOwnership(newOwner);
    }
}