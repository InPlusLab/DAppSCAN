// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockStaking.sol";

contract AudiusMock is MockStaking {
    constructor(IERC20 _token) MockStaking(_token) {}

    /**
     * @notice Get total delegation from a given address
     * @param _delegator - delegator address
     */
    function getTotalDelegatorStake(address _delegator) external view returns (uint256) {
        return staked;
    }

    /**
     * @notice Allow a delegator to delegate stake to a service provider
     * @param _targetSP - address of service provider to delegate to
     * @param _amount - amount in wei to delegate
     * @return Updated total amount delegated to the service provider by delegator
     */
    function delegateStake(address _targetSP, uint256 _amount)
        external
        reverted(this.delegateStake.selector)
        returns (uint256)
    {
        require(token.transferFrom(msg.sender, address(this), _amount));
        staked += _amount;
    }

    /**
     * @notice Submit request for undelegation
     * @param _target - address of service provider to undelegate stake from
     * @param _amount - amount in wei to undelegate
     * @return Updated total amount delegated to the service provider by delegator
     */
    function requestUndelegateStake(address _target, uint256 _amount)
        external
        reverted(this.requestUndelegateStake.selector)
        returns (uint256)
    {
        staked -= _amount;
        unstakeLocks[nextUnstakeLockID] = UnstakeLock({ amount: _amount, account: msg.sender });
    }

    /**
     * @notice Cancel undelegation request
     */
    function cancelUndelegateStakeRequest() external {}

    /**
     * @notice Finalize undelegation request and withdraw stake
     * @return New total amount currently staked after stake has been undelegated
     */
    function undelegateStake() external reverted(this.undelegateStake.selector) returns (uint256) {
        token.transfer(unstakeLocks[nextUnstakeLockID].account, unstakeLocks[nextUnstakeLockID].amount);
    }

    /**
     * @notice Claim and distribute rewards to delegators and service provider as necessary
     * @param _serviceProvider - Provider for which rewards are being distributed
     * @dev Factors in service provider rewards from delegator and transfers deployer cut
     */
    function claimRewards(address _serviceProvider) external reverted(this.claimRewards.selector) {
        return;
    }

    /// @notice Get the Staking address
    function getStakingAddress() external view returns (address) {
        return address(this);
    }
}
