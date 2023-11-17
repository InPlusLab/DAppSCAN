// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OilerToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Molier", "MOL") {
        _mint(msg.sender, initialSupply);
    }
}