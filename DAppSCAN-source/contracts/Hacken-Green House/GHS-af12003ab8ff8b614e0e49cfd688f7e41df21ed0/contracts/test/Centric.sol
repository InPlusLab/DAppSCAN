// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract Centric is ERC20 {
    // solhint-disable visibility-modifier-order
    constructor (uint256 totalSupply) ERC20("Centric", "CNR") { // solhint-disable func-visibility
        _mint(msg.sender, totalSupply);
    }
}
