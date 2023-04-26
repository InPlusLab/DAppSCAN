// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

/// @title IStETH
/// @author Angle Core Team
/// @notice Interface for the `StETH` contract
/// @dev This interface only contains functions of the `StETH` which are called by other contracts
/// of this module
interface IStETH {
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);

    event Submitted(address sender, uint256 amount, address referral);

    function submit(address) external payable returns (uint256);

    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);
}
