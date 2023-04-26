//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRegistry {
    function register(address safeGuard, uint8 version) external;

    function getSafeGuardCount() external view returns (uint256);

    function getSafeGuard(uint256 index) external returns (address);
}
