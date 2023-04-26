// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IStrategyControllerConverter {
    function convert(address) external returns (uint256);
}

