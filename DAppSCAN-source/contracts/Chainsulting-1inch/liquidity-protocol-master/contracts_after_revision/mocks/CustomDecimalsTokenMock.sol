// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./TokenMock.sol";


contract CustomDecimalsTokenMock is TokenMock {
    constructor(string memory name, string memory symbol, uint8 decimals) public TokenMock(name, symbol) {
        _setupDecimals(decimals);
    }
}
