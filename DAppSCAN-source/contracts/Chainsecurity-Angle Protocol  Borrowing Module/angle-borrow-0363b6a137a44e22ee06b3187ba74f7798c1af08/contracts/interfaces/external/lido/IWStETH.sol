// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

/// @title IWStETH
/// @author Angle Core Team
/// @notice Interface for the `WStETH` contract
/// @dev This interface only contains functions of the `WStETH` which are called by other contracts
/// of this module
interface IWStETH {
    function wrap(uint256 _stETHAmount) external returns (uint256);

    function stETH() external view returns (address);
}
