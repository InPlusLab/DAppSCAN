// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { ERC20PresetMinterPauser } from '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';

contract SettlementTokenMock is ERC20PresetMinterPauser {
    constructor() ERC20PresetMinterPauser('USDC', 'USDC') {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
