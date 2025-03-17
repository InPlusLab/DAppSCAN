// SPDX-License-Identifier: MIT
// SWC-103-Floating Pragma : L3
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SimpleToken is ERC20 {

    constructor(
        string memory name,
        string memory symbol,
        uint256 totalSupply_
    ) ERC20(name, symbol) {
        _mint(msg.sender, totalSupply_);
    }

}