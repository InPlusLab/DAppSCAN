// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./LCBEP20.sol";

contract MockBEP20 is LCBEP20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) public LCBEP20(name, symbol) {
        _mint(msg.sender, supply);
    }
}
