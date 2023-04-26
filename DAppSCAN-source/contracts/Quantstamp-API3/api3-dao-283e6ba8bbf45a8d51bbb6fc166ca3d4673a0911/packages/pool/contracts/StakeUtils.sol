//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./TransferUtils.sol";
import "./interfaces/IStakeUtils.sol";

/// @title Contract that implements staking functionality
abstract contract StakeUtils is TransferUtils, IStakeUtils {
    /// @notice Called to stake tokens to receive pools in the share
    /// @param amount Amount of tokens to stake
    function stake(uint256 amount)
        public
        override
    {
        payReward();
        User storage user = users[msg.sender];
        require(user.unstaked >= amount, ERROR_VALUE);
        user.unstaked = user.unstaked - amount;
        uint256 totalSharesNow = totalShares();
        uint256 sharesToMint = totalSharesNow * amount / totalStake;
        uint256 userSharesNow = userShares(msg.sender);
        user.shares.push(Checkpoint({
            fromBlock: block.number,
            value: userSharesNow + sharesToMint
            }));
        uint256 totalSharesAfter = totalSharesNow + sharesToMint; 
        updateTotalShares(totalSharesAfter);
        totalStake = totalStake + amount;
        updateDelegatedVotingPower(sharesToMint, true);
        emit Staked(
            msg.sender,
            amount,
            totalSharesAfter
            );
    }

    /// @notice Convenience method to deposit and stake in a single transaction
    /// @dev Due to the `deposit()` interface, `userAddress` can only be the
    /// caller
    /// @param source Token transfer source
    /// @param amount Amount to be deposited and staked
    /// @param userAddress User that the tokens will be staked for
    function depositAndStake(
        address source,
        uint256 amount,
        address userAddress
        )
        external
        override
    {
        require(userAddress == msg.sender, ERROR_UNAUTHORIZED);
        deposit(source, amount, userAddress);
        stake(amount);
    }

    /// @notice Called to schedule an unstake by the user
    /// @dev Users need to schedule an unstake and wait for `unstakeWaitPeriod`
    /// to be able to unstake.
    /// @param amount Amount of tokens for which the unstake will be scheduled
    /// for 
    function scheduleUnstake(uint256 amount)
        external
        override
    {
        payReward();
        User storage user = users[msg.sender];
        uint256 userSharesNow = userShares(msg.sender);
        uint256 userStakedNow = userSharesNow * totalStake / totalShares();
        require(
            userStakedNow >= amount,
            ERROR_VALUE
            );
        user.unstakeScheduledFor = block.timestamp + unstakeWaitPeriod;
        user.unstakeAmount = amount;
        emit ScheduledUnstake(
            msg.sender,
            amount,
            user.unstakeScheduledFor
            );
    }

    /// @notice Called to execute a pre-scheduled unstake
    /// @return Amount of tokens that are unstaked
    function unstake()
        public
        override
        returns(uint256)
    {
        payReward();
        User storage user = users[msg.sender];
        require(block.timestamp > user.unstakeScheduledFor, ERROR_UNAUTHORIZED);
        require(block.timestamp < user.unstakeScheduledFor + EPOCH_LENGTH, ERROR_UNAUTHORIZED);
        uint256 amount = user.unstakeAmount;
        uint256 totalSharesNow = totalShares();
        uint256 userSharesNow = userShares(msg.sender);
        uint256 sharesToBurn = totalSharesNow * amount / totalStake;
        // If the user no longer has enough shares to unstake the scheduled
        // amount of tokens, unstake as many tokens as possible instead
        if (sharesToBurn > userSharesNow)
        {
            sharesToBurn = userSharesNow;
            amount = sharesToBurn * totalStake / totalSharesNow;
        }
        user.unstaked = user.unstaked + amount;
        user.shares.push(Checkpoint({
            fromBlock: block.number,
            value: userSharesNow - sharesToBurn
            }));
        uint256 totalSharesAfter = totalSharesNow > sharesToBurn
                ? totalSharesNow - sharesToBurn
                : 1;
        updateTotalShares(totalSharesAfter);
        updateDelegatedVotingPower(sharesToBurn, false);

        totalStake = totalStake > amount
            ? totalStake - amount
            : 1;
        user.unstakeScheduledFor = 0;
        user.unstakeAmount = 0;
        emit Unstaked(
            msg.sender,
            amount,
            totalSharesAfter
            );
        return amount;
    }

    /// @notice Convenience method to execute an unstake and withdraw in a
    /// single transaction
    /// @dev Note that withdraw may revert because the user may have less than
    /// `unstaked` tokens that are withdrawable
    /// @param destination Token transfer destination
    function unstakeAndWithdraw(address destination)
        external
        override
    {
        uint256 unstaked = unstake();
        withdraw(destination, unstaked);
    }
}
