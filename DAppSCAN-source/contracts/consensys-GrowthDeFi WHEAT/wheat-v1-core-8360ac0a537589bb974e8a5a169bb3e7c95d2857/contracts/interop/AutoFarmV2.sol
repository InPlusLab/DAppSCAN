// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @dev Minimal set of declarations for AutoFarm V2 interoperability.
 */
interface AutoFarmV2
{
	function AUTOv2() external view returns (address _auto);
	function pendingAUTO(uint256 _pid, address _user) external view returns (uint256 _pendingAuto);
	function poolInfo(uint256 _pid) external view returns (address _token, uint256 _allocPoint, uint256 _lastRewardBlock, uint256 _accAutoPerShare, address _strategy);
	function poolLength() external view returns (uint256 _poolLength);
	function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256 _amount);
	function userInfo(uint256 _pid, address _user) external view returns (uint256 _shares, uint256 _rewardDebt);

	function deposit(uint256 _pid, uint256 _amount) external;
	function withdraw(uint256 _pid, uint256 _amount) external;
	function emergencyWithdraw(uint256 _pid) external;
}

interface AutoFarmV2Strategy
{
	function entranceFeeFactor() external view returns (uint256 _entranceFeeFactor);
	function entranceFeeFactorMax() external view returns (uint256 _entranceFeeFactorMax);
	function withdrawFeeFactor() external view returns (uint256 _withdrawFeeFactor);
	function withdrawFeeFactorMax() external view returns (uint256 _withdrawFeeFactorMax);
}
