// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './MockCollateral.sol';

contract MockUSDT is MockCollateral {
    constructor(
        address _creatorAddress,
        uint256 _genesisSupply,
        string memory _symbol,
        uint8 _decimals
    ) MockCollateral(_creatorAddress, _genesisSupply, _symbol, _decimals) {}
}
