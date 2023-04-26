// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { ClearingHouse } from '../../protocol/clearinghouse/ClearingHouse.sol';

contract ClearingHouseDummy is ClearingHouse {
    // just to test upgradibility
    function newMethodAdded() public pure returns (uint256) {
        return 1234567890;
    }
}
