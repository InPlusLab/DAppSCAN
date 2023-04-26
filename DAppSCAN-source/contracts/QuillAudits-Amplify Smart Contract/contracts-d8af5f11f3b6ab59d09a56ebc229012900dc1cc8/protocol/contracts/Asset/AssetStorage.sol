// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../ERC721/ERC721URIStorage.sol";

abstract contract AssetStorage is ERC721URIStorage {
    struct Token {
        uint256 value;
        uint256 maturity;
        uint256 interestRate;
        uint256 advanceRate;
        string rating;
        string _hash;
        bool redeemed;
    }

    mapping(uint256 => Token) internal _tokens;
}