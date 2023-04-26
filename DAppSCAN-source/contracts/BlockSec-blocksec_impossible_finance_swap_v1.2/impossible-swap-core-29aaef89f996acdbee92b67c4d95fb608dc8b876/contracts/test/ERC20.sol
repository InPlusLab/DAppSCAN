// SPDX-License-Identifier: GPL-3
pragma solidity =0.7.6;

import '../ImpossibleERC20.sol';

contract ERC20 is ImpossibleERC20 {
    constructor(uint256 _totalSupply) {
        _mint(msg.sender, _totalSupply);
    }
}
