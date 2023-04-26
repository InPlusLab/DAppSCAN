//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./ClaimUtils.sol";
import "./interfaces/ITimelockUtils.sol";

/// @title Contract that implements vesting functionality
/// @dev TimelockManager contracts interface with this contract to transfer
/// API3 tokens that are locked under a vesting schedule.
abstract contract TimelockUtils is ClaimUtils, ITimelockUtils {
    struct Timelock
    {
        uint256 totalAmount;
        uint256 remainingAmount;
        uint256 releaseStart;
        uint256 releaseEnd;
    }

    /// @notice Maps user addresses to TimelockManager contract addresses to 
    /// timelocks
    /// @dev This implies that a user cannot have multiple timelocks
    /// transferrerd from the same TimelockManager contract. This is
    /// acceptable, because the TimelockManager is implemented in a way to not
    /// allow multiple timelocks per user.
    mapping(address => mapping(address => Timelock)) public userToDepositorToTimelock;

    /// @notice Called by TimelockManager contracts to deposit tokens on behalf
    /// of a user on a linear vesting schedule
    /// @dev Refer to `TimelockManager.sol` to see how this is used
    /// @param source Token source
    /// @param amount Token amount
    /// @param userAddress Address of the user who will receive the tokens
    /// @param releaseStart Vesting schedule starting time
    /// @param releaseEnd Vesting schedule ending time
    function depositWithVesting(
        address source,
        uint256 amount,
        address userAddress,
        uint256 releaseStart,
        uint256 releaseEnd
        )
        external
        override
    {
        require(userToDepositorToTimelock[userAddress][msg.sender].remainingAmount == 0, ERROR_UNAUTHORIZED);
        require(
            releaseEnd > releaseStart
                && amount != 0,
            ERROR_VALUE
            );
        users[userAddress].unstaked = users[userAddress].unstaked + amount;
        users[userAddress].vesting = users[userAddress].vesting + amount;
        userToDepositorToTimelock[userAddress][msg.sender] = Timelock({
            totalAmount: amount,
            remainingAmount: amount,
            releaseStart: releaseStart,
            releaseEnd: releaseEnd
            });
        api3Token.transferFrom(source, address(this), amount);
        emit DepositedVesting(
            userAddress,
            amount,
            releaseStart,
            releaseEnd
            );
    }

    /// @notice Called to release tokens vested by the timelock
    /// @param userAddress Address of the user whose timelock status will be
    /// updated
    /// @param timelockManagerAddress Address of the TimelockManager that has
    /// created the timelock
    function updateTimelockStatus(
        address userAddress,
        address timelockManagerAddress
        )
        external
        override
    {
        Timelock storage timelock = userToDepositorToTimelock[userAddress][timelockManagerAddress];
        require(block.timestamp > timelock.releaseStart, ERROR_UNAUTHORIZED);
        require(timelock.remainingAmount > 0, ERROR_UNAUTHORIZED);
        uint256 totalUnlocked;
        if (block.timestamp >= timelock.releaseEnd)
        {
            totalUnlocked = timelock.totalAmount;
        }
        else
        {
            uint256 passedTime = block.timestamp - timelock.releaseStart;
            uint256 totalTime = timelock.releaseEnd - timelock.releaseStart;
            totalUnlocked = timelock.totalAmount * passedTime / totalTime;
        }
        uint256 previouslyUnlocked = timelock.totalAmount - timelock.remainingAmount;
        uint256 newlyUnlocked = totalUnlocked - previouslyUnlocked;
        User storage user = users[userAddress];
        user.vesting = user.vesting - newlyUnlocked;
        uint256 newRemainingAmount = timelock.remainingAmount - newlyUnlocked;
        userToDepositorToTimelock[userAddress][timelockManagerAddress].remainingAmount = newRemainingAmount;
        emit UpdatedTimelock(
            userAddress,
            timelockManagerAddress,
            newRemainingAmount
            );
    }
}
