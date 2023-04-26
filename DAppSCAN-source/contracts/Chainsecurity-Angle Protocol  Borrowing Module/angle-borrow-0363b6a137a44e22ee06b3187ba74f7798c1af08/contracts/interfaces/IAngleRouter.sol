// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

/// @title IAngleRouter
/// @author Angle Core Team
/// @notice Interface for the `AngleRouter` contract
/// @dev This interface only contains functions of the `AngleRouter01` contract which are called by other contracts
/// of this module
interface IAngleRouter {
    function mint(
        address user,
        uint256 amount,
        uint256 minStableAmount,
        address stablecoin,
        address collateral
    ) external;

    function burn(
        address user,
        uint256 amount,
        uint256 minAmountOut,
        address stablecoin,
        address collateral
    ) external;
}
