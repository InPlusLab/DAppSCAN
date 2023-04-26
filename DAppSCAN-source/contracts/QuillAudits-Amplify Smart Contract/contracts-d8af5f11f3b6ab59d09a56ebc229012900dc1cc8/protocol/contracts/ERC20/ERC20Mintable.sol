// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Burnable.sol";

abstract contract ERC20Mintable is ERC20Burnable {
    address internal _admin;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _admin = msg.sender;
    }

    function mint(address to, uint256 amount) public virtual {
        require(msg.sender == _admin, "ERC20: must have admin role to mint");
        _mint(to, amount);
    }
}