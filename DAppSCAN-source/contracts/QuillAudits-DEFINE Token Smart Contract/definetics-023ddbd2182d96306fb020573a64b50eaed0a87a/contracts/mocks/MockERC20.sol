// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockERC20 is ERC20 {
    constructor(uint256 totalSupply) ERC20('TokenT', 'TTT') {
        _mint(msg.sender, totalSupply);
    }
}
