// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC721 {
    event Transfer(address indexed from, address indexed to, uint indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint indexed tokenId);

    function balanceOf(address owner) external view returns (uint balance);
    function ownerOf(uint tokenId) external view returns (address owner);
    
    function transferFrom(address from, address to, uint tokenId) external;
    function approve(address to, uint tokenId) external;
}

interface IERC721Metadata is IERC721 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint tokenId) external view returns (string memory);
}