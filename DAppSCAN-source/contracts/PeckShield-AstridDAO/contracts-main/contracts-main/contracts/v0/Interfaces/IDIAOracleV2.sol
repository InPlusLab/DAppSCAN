// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IDIAOracleV2 {
    /* @returns (value scaled by in 1e8, timestamp in seconds) */
    function getValue(string memory key) external view returns (uint128, uint128);
}
