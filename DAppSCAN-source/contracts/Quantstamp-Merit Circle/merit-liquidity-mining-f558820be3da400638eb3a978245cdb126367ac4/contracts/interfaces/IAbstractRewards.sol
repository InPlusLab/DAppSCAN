// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface IAbstractRewards {
	/**
	 * @dev Returns the total amount of rewards a given address is able to withdraw.
	 * @param account Address of a reward recipient
	 * @return A uint256 representing the rewards `account` can withdraw
	 */
	function withdrawableRewardsOf(address account) external view returns (uint256);

  /**
	 * @dev View the amount of funds that an address has withdrawn.
	 * @param account The address of a token holder.
	 * @return The amount of funds that `account` has withdrawn.
	 */
	function withdrawnRewardsOf(address account) external view returns (uint256);

	/**
	 * @dev View the amount of funds that an address has earned in total.
	 * accumulativeFundsOf(account) = withdrawableRewardsOf(account) + withdrawnRewardsOf(account)
	 * = (pointsPerShare * balanceOf(account) + pointsCorrection[account]) / POINTS_MULTIPLIER
	 * @param account The address of a token holder.
	 * @return The amount of funds that `account` has earned in total.
	 */
	function cumulativeRewardsOf(address account) external view returns (uint256);

	/**
	 * @dev This event emits when new funds are distributed
	 * @param by the address of the sender who distributed funds
	 * @param rewardsDistributed the amount of funds received for distribution
	 */
	event RewardsDistributed(address indexed by, uint256 rewardsDistributed);

	/**
	 * @dev This event emits when distributed funds are withdrawn by a token holder.
	 * @param by the address of the receiver of funds
	 * @param fundsWithdrawn the amount of funds that were withdrawn
	 */
	event RewardsWithdrawn(address indexed by, uint256 fundsWithdrawn);
}