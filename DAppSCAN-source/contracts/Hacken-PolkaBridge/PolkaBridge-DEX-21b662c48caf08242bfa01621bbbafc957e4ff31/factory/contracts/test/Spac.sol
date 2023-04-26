// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import '../UniswapV2ERC20.sol';

contract Spac is UniswapV2ERC20 {
    constructor(uint _totalSupply) {
        _mint(msg.sender, _totalSupply);
    }
}
