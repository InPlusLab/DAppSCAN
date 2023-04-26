// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

contract GoGoNFTOracle is Ownable {
    mapping(uint256 => uint256) tiers;

    struct Tier {
        uint256 tokenId;
        uint256 tier;
    }

    constructor() {}

    function addTier(uint256 tokenId, uint256 tier) external onlyOwner {
        tiers[tokenId] = tier;
    }

    function addMultipleTiers(Tier[] memory nfts) external onlyOwner {
        for (uint256 i = 0; i < nfts.length; i++) {
            tiers[nfts[i].tokenId] = nfts[i].tier;
        }
    }

    function getBoostMultiplyer(uint256 tokenId)
        external
        view
        returns (uint256 multiplyer)
    {
        multiplyer = 10;
        if (tiers[tokenId] == 0) multiplyer = 11;
        else if (tiers[tokenId] == 1) multiplyer = 12;
        else if (tiers[tokenId] == 2) multiplyer = 14;
    }
}
