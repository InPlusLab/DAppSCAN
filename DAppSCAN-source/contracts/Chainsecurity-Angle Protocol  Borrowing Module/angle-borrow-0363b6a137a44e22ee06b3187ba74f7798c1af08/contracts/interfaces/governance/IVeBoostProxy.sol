// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

/// @title IVeBoostProxy
/// @author Angle Core Team
/// @notice Interface for the `VeBoostProxy` contract
/// @dev This interface only contains functions of the contract which are called by other contracts
/// of this module
/// @dev The `veBoostProxy` contract used by Angle is a full fork of Curve Finance implementation
interface IVeBoostProxy {
    /// @notice Reads the adjusted veANGLE balance of an address (adjusted by delegation)
    //solhint-disable-next-line
    function adjusted_balance_of(address) external view returns (uint256);
}
