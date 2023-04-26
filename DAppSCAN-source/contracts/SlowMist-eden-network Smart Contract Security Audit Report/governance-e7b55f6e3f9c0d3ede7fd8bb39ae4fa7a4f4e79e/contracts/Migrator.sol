// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IERC20Extended.sol";
import "./lib/SafeERC20.sol";

/**
 * @title Migrator
 * @dev Migrate from old token to new token
 */
contract Migrator {
    using SafeERC20 for IERC20Extended;

    /// @notice From token
    IERC20Extended public immutable fromToken;

    /// @notice To token
    IERC20Extended public immutable toToken;

    /// @notice Event emitted on each migration
    event Migrate(uint256 amount, address fromToken, address toToken, address migrator);

    /**
     * @notice Construct new Migrator
     * @param _fromToken From token
     * @param _toToken To token
     */
    constructor(address _fromToken, address _toToken) {
        fromToken = IERC20Extended(_fromToken);
        toToken = IERC20Extended(_toToken);
    }

    /**
     * @notice Migrate to new token
     * @param amount Amount to migrate
     */
    function migrate(uint256 amount) external {
        _migrate(msg.sender, amount);
    }

    /**
     * @notice Migrate to new token, sending new tokens to specified receiver address
     * @param receiver Address that will receive new tokens
     * @param amount Amount to migrate
     */
    function migrateTo(address receiver, uint256 amount) external {
        _migrate(receiver, amount);
    }

    /**
     * @notice Migrate to new token using permit for approvals
     * @param amount Amount to migrate
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function migrateWithPermit(
        uint256 amount,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external {
        fromToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _migrate(msg.sender, amount);
    }

    /**
     * @notice Migrate to new token, sending new tokens to specified receiver using permit for approvals
     * @param receiver Address that will receive new tokens
     * @param amount Amount to migrate
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function migrateToWithPermit(
        address receiver,
        uint256 amount,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external {
        fromToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _migrate(receiver, amount);
    }
    
    /**
     * @notice Internal implementation of migrate
     * @param receiver Address that will receive new tokens
     * @param amount Amount to migrate
     */
    function _migrate(address receiver, uint256 amount) internal {
        fromToken.safeTransferFrom(msg.sender, address(this), amount);
        toToken.mint(receiver, amount);
        emit Migrate(amount, address(fromToken), address(toToken), receiver);
    }
}