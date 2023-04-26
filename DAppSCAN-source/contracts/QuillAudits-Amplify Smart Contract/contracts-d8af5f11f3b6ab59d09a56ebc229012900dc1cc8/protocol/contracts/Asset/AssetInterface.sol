// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../ERC721/IERC721.sol";

abstract contract AssetInterface is IERC721 {
    bool public isAssetsFactory = true;

    function getTokenInfo(uint256 _tokenId) external virtual view returns (uint256, uint256, uint256, uint256, string memory, string memory, address, bool);
    function markAsRedeemed(uint256 tokenId) external virtual;
}