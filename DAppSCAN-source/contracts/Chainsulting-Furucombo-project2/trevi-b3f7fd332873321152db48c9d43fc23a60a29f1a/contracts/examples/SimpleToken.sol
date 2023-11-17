// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/ERC20.sol";

contract SimpleToken is ERC20 {
    constructor(string memory name_,
               string memory symbol_,
               uint256 amount) public ERC20(name_, symbol_) {
        _mint(msg.sender, amount);
               }
}
