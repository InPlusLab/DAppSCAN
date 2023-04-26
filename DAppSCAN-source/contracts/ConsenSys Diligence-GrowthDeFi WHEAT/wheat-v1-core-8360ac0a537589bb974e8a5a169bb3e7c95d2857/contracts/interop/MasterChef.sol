// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @dev Minimal set of declarations for PancakeSwap MasterChef interoperability.
 */
interface MasterChef
{
	function cake() external view returns (address _cake);
	function syrup() external view returns (address _syrup);
	function pendingCake(uint256 _pid, address _user) external view returns (uint256 _pendingCake);
	function poolInfo(uint256 _pid) external view returns (address _lpToken, uint256 _allocPoint, uint256 _lastRewardBlock, uint256 _accCakePerShare);
	function poolLength() external view returns (uint256 _poolLength);
	function userInfo(uint256 _pid, address _user) external view returns (uint256 _amount, uint256 _rewardDebt);

	function deposit(uint256 _pid, uint256 _amount) external;
	function enterStaking(uint256 _amount) external;
	function leaveStaking(uint256 _amount) external;
	function withdraw(uint256 _pid, uint256 _amount) external;
	function emergencyWithdraw(uint256 _pid) external;
}
