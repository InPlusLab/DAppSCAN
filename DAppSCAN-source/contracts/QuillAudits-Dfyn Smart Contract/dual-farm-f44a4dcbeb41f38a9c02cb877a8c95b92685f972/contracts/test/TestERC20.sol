// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.6.11;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract TestERC20 is ERC20 {
    constructor(uint256 amount) public ERC20('Test ERC20', 'TEST') {
        _mint(msg.sender, amount);
    }
}
