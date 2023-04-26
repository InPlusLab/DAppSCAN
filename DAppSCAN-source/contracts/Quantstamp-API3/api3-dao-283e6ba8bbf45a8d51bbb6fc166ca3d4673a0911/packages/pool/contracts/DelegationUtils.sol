//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./RewardUtils.sol";
import "./interfaces/IDelegationUtils.sol";

/// @title Contract that implements voting power delegation
abstract contract DelegationUtils is RewardUtils, IDelegationUtils {
    /// @notice Called by the user to delegate voting power
    /// @param delegate User address the voting power will be delegated to
    function delegateVotingPower(address delegate) 
        external
        override
    {
        payReward();
        // Delegating users have cannot use their voting power, so we are
        // verifying that the delegate is not currently delegating. However,
        // the delegate may delegate after they have been delegated to.
        require(
            delegate != address(0)
                && delegate != msg.sender
                && userDelegate(delegate) == address(0),
            ERROR_ADDRESS
            );
        User storage user = users[msg.sender];
        // Do not allow frequent delegation updates as that can be used to spam
        // proposals
        require(
            user.lastDelegationUpdateTimestamp <= block.timestamp - EPOCH_LENGTH,
            ERROR_UNAUTHORIZED
            );
        user.lastDelegationUpdateTimestamp = block.timestamp;
        uint256 userShares = userShares(msg.sender);
        address userDelegate = userDelegate(msg.sender);

        require(userDelegate != delegate, ERROR_DELEGATE);

        if (userDelegate != address(0)) {
            // Need to revoke previous delegation
            updateCheckpointArray(
                users[userDelegate].delegatedTo,
                userReceivedDelegation(userDelegate) - userShares
                );
        }
        // Assign the new delegation
        User storage _delegate = users[delegate];
        updateCheckpointArray(
            _delegate.delegatedTo,
            userReceivedDelegation(delegate) + userShares
            );
        // Record the new delegate for the user
        updateAddressCheckpointArray(
            user.delegates,
            delegate
            );
        emit Delegated(
            msg.sender,
            delegate
            );
    }

    /// @notice Called by the user to undelegate voting power
    function undelegateVotingPower()
        external
        override
    {
        payReward();
        User storage user = users[msg.sender];
        address userDelegate = userDelegate(msg.sender);
        require(
            userDelegate != address(0)
                && user.lastDelegationUpdateTimestamp <= block.timestamp - EPOCH_LENGTH,
            ERROR_UNAUTHORIZED
            );

        uint256 userShares = userShares(msg.sender);
        User storage delegate = users[userDelegate];
        updateCheckpointArray(
            delegate.delegatedTo,
            userReceivedDelegation(userDelegate) - userShares
            );
        updateAddressCheckpointArray(
            user.delegates,
            address(0)
            );
        user.lastDelegationUpdateTimestamp = block.timestamp;
        emit Undelegated(
            msg.sender,
            userDelegate
            );
    }

    /// @notice Called internally when the user shares are updated to update
    /// the delegated voting power
    /// @dev User shares only get updated while staking, scheduling unstake
    /// or unstaking
    /// @param shares Amount of shares that will be added/removed
    /// @param delta Whether the shares will be added/removed (add for `true`,
    /// and vice versa)
    function updateDelegatedVotingPower(
        uint256 shares,
        bool delta
        )
        internal
    {
        address userDelegate = userDelegate(msg.sender);
        if (userDelegate == address(0)) {
            return;
        }

        User storage delegate = users[userDelegate];
        uint256 currentlyDelegatedTo = userReceivedDelegation(userDelegate);
        uint256 newDelegatedTo;
        if (delta) {
            newDelegatedTo = currentlyDelegatedTo + shares;
        } else {
            newDelegatedTo = currentlyDelegatedTo > shares 
                ? currentlyDelegatedTo - shares
                : 0;
        }
        updateCheckpointArray(
            delegate.delegatedTo,
            newDelegatedTo
            );
    }
}
