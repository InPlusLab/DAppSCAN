// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../Mooniswap.sol";

/// @title Extends `IMooniswapFactoryGovernance` with information about pools
interface IMooniswapFactory is IMooniswapFactoryGovernance {
    /// @notice returns a pool for tokens pair. Zero address result means that pool doesn't exist yet
    function pools(IERC20 token0, IERC20 token1) external view returns (Mooniswap);
    /// @notice True if address is currently listed as a moonswap pool. Otherwise, false
    function isPool(Mooniswap mooniswap) external view returns (bool);
}
