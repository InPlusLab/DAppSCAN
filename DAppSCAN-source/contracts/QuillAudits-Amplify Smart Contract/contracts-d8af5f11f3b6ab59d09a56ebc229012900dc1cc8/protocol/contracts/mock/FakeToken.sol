// SPDX-License-Identifier: MIT
/// @dev size: 3.0001 Kbytes
pragma solidity ^0.8.0;

import "../ERC20/ERC20Mintable.sol";

contract ERC20Fake is ERC20Mintable {
    constructor(string memory name, string memory symbol) ERC20Mintable(name, symbol) {}

    function owner() external view returns (address) {
        return _admin;
    }
}