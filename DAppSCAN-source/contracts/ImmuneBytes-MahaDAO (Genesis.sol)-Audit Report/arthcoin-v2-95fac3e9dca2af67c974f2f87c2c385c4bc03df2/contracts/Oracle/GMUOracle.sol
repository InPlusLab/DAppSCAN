// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SimpleOracle} from './SimpleOracle.sol';

contract GMUOracle is SimpleOracle {
    constructor(string memory _name, uint256 _price)
        SimpleOracle(_name, _price)
    {}
}
