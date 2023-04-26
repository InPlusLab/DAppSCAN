// SPDX-License-Identifier: Apache-2.0


pragma solidity ^0.8.0;

interface IERC721Minimal {
    function ownerOf(uint256 tokenId) external view returns (address owner);
}