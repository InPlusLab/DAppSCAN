// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IVToken } from '../IVToken.sol';

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';

interface IClearingHouseCustomErrors is IClearingHouseStructures {
    /// @notice error to denote invalid account access
    /// @param senderAddress address of msg sender
    error AccessDenied(address senderAddress);

    /// @notice error to denote usage of uninitialized token
    /// @param collateralId address of token
    error CollateralDoesNotExist(uint32 collateralId);

    /// @notice error to denote usage of unsupported collateral token
    /// @param collateralId address of token
    error CollateralNotAllowedForUse(uint32 collateralId);

    /// @notice error to denote usage of uninitialized pool
    /// @param poolId unitialized truncated address supplied
    error PoolDoesNotExist(uint32 poolId);

    /// @notice error to denote usage of unsupported pool
    /// @param poolId address of token
    error PoolNotAllowedForTrade(uint32 poolId);

    /// @notice error to denote low notional value of txn
    /// @param notionalValue notional value of txn
    error LowNotionalValue(uint256 notionalValue);

    /// @notice error to denote incorrect address is supplied while updating collateral settings
    /// @param incorrectAddress incorrect address of collateral token
    /// @param correctAddress correct address of collateral token
    error IncorrectCollateralAddress(IERC20 incorrectAddress, IERC20 correctAddress);

    /// @notice error to denote invalid address supplied as a collateral token
    /// @param invalidAddress invalid address of collateral token
    error InvalidCollateralAddress(address invalidAddress);

    /// @notice error to denote invalid token liquidation (fraction to liquidate> 1)
    error InvalidTokenLiquidationParameters();

    /// @notice this is errored when the enum (uint8) value is out of bounds
    /// @param multicallOperationType is the value that is out of bounds
    error InvalidMulticallOperationType(MulticallOperationType multicallOperationType);

    /// @notice error to denote slippage of txn beyond set threshold
    error SlippageBeyondTolerance();

    /// @notice error to denote that keeper fee is negative or zero
    error KeeperFeeNotPositive(int256 keeperFee);
}
