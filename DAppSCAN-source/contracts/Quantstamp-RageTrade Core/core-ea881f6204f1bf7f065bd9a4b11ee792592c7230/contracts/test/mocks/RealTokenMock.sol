// SPDX-License-Identifier: UNLICENSED

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';

contract RealTokenMock is ERC20PresetMinterPauser {
    constructor() ERC20PresetMinterPauser('WETH', 'WETH') {}
}
