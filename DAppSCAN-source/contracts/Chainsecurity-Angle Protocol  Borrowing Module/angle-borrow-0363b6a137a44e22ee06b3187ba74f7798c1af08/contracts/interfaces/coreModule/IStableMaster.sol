// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

/// @title IStableMaster
/// @author Angle Core Team
/// @notice Previous interface with additionnal getters for public variables and mappings
interface IStableMaster {
    function agToken() external returns (address);

    function updateStocksUsers(uint256 amount, address poolManager) external;
}
