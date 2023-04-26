// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '../../token/IERC20.sol';

/// @title Interface for WETH9
interface IWETH9 is IERC20 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;
}