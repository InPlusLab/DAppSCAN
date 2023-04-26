// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "./IUniswapV3Pool.sol";

interface IPopsicleV3Optimizer {
    /// @notice The first of the two tokens of the pool, sorted by address
    /// @return The token contract address
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool, sorted by address
    /// @return The token contract address
    function token1() external view returns (address);
    
    /// @notice The pool tick spacing
    /// @dev Ticks can only be used at multiples of this value, minimum of 1 and always positive
    /// e.g.: a tickSpacing of 3 means ticks can be initialized every 3rd tick, i.e., ..., -6, -3, 0, 3, 6, ...
    /// This value is an int24 to avoid casting even though it is always positive.
    /// @return The tick spacing
    function tickSpacing() external view returns (int24);

    /// @notice A Uniswap pool facilitates swapping and automated market making between any two assets that strictly conform
    /// to the ERC20 specification
    /// @return The address of the Uniswap V3 Pool
    function pool() external view returns (IUniswapV3Pool);

    /// @notice The lower tick of the range
    function tickLower() external view returns (int24);

    /// @notice The upper tick of the range
    function tickUpper() external view returns (int24);

    /**
     * @notice Deposits tokens in proportion to the Optimizer's current ticks.
     * @param amount0Desired Max amount of token0 to deposit
     * @param amount1Desired Max amount of token1 to deposit
     * @param to address that plp should be transfered
     * @return shares minted
     * @return amount0 Amount of token0 deposited
     * @return amount1 Amount of token1 deposited
     */
    function deposit(uint256 amount0Desired, uint256 amount1Desired, address to) external payable returns (uint256 shares, uint256 amount0,uint256 amount1);

    /**
     * @notice Withdraws tokens in proportion to the Optimizer's holdings.
     * @dev Removes proportional amount of liquidity from Uniswap.
     * @param shares burned by sender
     * @return amount0 Amount of token0 sent to recipient
     * @return amount1 Amount of token1 sent to recipient
     */
    function withdraw(uint256 shares, address to) external returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Updates Optimizer's positions.
     * @dev Finds base position and limit position for imbalanced token
     * mints all amounts to this position(including earned fees)
     */
    function rerange() external payable;

    /**
     * @notice Updates Optimizer's positions. Can only be called by the governance.
     * @dev Swaps imbalanced token. Finds base position and limit position for imbalanced token if
     * we don't have balance during swap because of price impact.
     * mints all amounts to this position(including earned fees)
     */
    function rebalance() external payable;
}