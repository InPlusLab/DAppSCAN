// SPDX-License-Identifier: MIT
/// @dev size: 2.947 Kbytes
pragma solidity ^0.8.0;

import "../ERC20/ERC20Mintable.sol";

contract PoolToken is ERC20Mintable {
    /**
    * @dev Prefix for token symbol
    */
    string internal constant prefix = "lp";
    
    constructor(
        string memory name, 
        string memory underlyingSymbol
        ) ERC20Mintable(name, createPoolTokenSymbol(underlyingSymbol)) {}

    function createPoolTokenSymbol(string memory symbol) internal pure returns (string memory){
        return string(abi.encodePacked(prefix, symbol));
    }
}