// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract GearBeta is ERC721, Ownable {

    constructor() ERC721("Gear contributors token", "GEAR-NFT") {
    }

    function mint(address to, uint256 tokenId) external onlyOwner {
        _mint(to, tokenId);
        // SWC-135-Code With No Effects: L15
        _setBaseURI("https://nft.gearbox.fi/");
    }
}
