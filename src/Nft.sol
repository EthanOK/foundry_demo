// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NFT is ERC721 {
    uint256 tokenCount;
    uint256 public constant MAX_total = 10000;
    address public owner;
    string public constant baseURI =
        "ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/";

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        owner = msg.sender;
        batchMint(owner, 10);
    }

    function totalSupply() public view returns (uint256) {
        return tokenCount;
    }

    function batchMint(address to, uint256 amount) public onlyOwner {
        require(tokenCount + amount <= MAX_total, "Over MAX_total");
        uint256 tokenId = tokenCount;
        for (uint256 i = 0; i < amount; ++i) {
            ++tokenId;
            _safeMint(to, tokenId);
        }
        tokenCount += amount;
    }

    function batchTransfer(
        address[] memory to,
        uint256[] memory tokenId
    ) public {
        require(to.length == tokenId.length, "Array lengths must match");

        for (uint256 i = 0; i < to.length; ++i) {
            safeTransferFrom(msg.sender, to[i], tokenId[i]);
        }
    }

    function _baseURI() internal pure override returns (string memory) {
        return baseURI;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }
}
