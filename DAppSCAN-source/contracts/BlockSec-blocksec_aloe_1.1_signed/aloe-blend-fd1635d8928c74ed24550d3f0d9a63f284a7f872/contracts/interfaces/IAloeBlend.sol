// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IAloeBlendActions.sol";
import "./IAloeBlendDerivedState.sol";
import "./IAloeBlendEvents.sol";
import "./IAloeBlendImmutables.sol";
import "./IAloeBlendState.sol";

/// @title Aloe Blend vault interface
/// @dev The interface is broken up into many smaller pieces
interface IAloeBlend is
    IAloeBlendActions,
    IAloeBlendDerivedState,
    IAloeBlendEvents,
    IAloeBlendImmutables,
    IAloeBlendState
{

}
