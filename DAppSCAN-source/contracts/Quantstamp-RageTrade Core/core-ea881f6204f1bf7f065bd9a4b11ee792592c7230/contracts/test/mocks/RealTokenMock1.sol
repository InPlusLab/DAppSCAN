// SPDX-License-Identifier: UNLICENSED

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';

contract RealTokenMockDecimals is ERC20PresetMinterPauser {
    uint8 immutable _decimals;

    constructor(uint8 decimalsToSet) ERC20PresetMinterPauser('WETH', 'WETH') {
        _decimals = decimalsToSet;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
