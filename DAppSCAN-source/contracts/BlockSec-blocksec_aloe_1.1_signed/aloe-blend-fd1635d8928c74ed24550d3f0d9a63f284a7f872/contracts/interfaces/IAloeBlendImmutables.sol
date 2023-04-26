// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./ISilo.sol";
import "./IVolatilityOracle.sol";

interface IAloeBlendImmutables {
    /// @notice The minimum width (in ticks) of the primary Uniswap position
    function MIN_WIDTH() external view returns (uint24);

    /// @notice The maximum width (in ticks) of the primary Uniswap position
    function MAX_WIDTH() external view returns (uint24);

    /// @notice The number of standard deviations to +/- from mean when setting primary Uniswap position
    function B() external view returns (uint8);

    /// @notice The maintenance budget buffer multiplier
    /// @dev The vault will attempt to build up a maintenance budget equal to the average cost of incentivization,
    /// multiplied by K.
    function K() external view returns (uint8);

    /// @notice The denominator applied to primary Uniswap earnings to determine what portion goes to maintenance budget
    /// @dev For example, if this is 10, then *at most* 1/10th of revenue from the primary Uniswap position will be
    /// added to the maintenance budget.
    function MAINTENANCE_FEE() external view returns (uint8);

    /// @notice The volatility oracle used to decide position width
    function volatilityOracle() external view returns (IVolatilityOracle);

    /// @notice The silo where excess token0 is stored
    function silo0() external view returns (ISilo);

    /// @notice The silo where excess token1 is stored
    function silo1() external view returns (ISilo);
}
