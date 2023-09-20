// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Minimal set of declarations for PantherSwap interoperability.
 */
interface PantherToken is IERC20
{
	function maxTransferAmount() external view returns (uint256 _maxTransferAmount);
	function transferTaxRate() external view returns (uint16 _transferTaxRate);
}

interface PantherMasterChef
{
	function panther() external view returns (address _panther);
	function pendingPanther(uint256 _pid, address _user) external view returns (uint256 _pendingPanther);
	function canHarvest(uint256 _pid, address _user) external view returns (bool _canHarvest);
	function poolInfo(uint256 _pid) external view returns (address _lpToken, uint256 _allocPoint, uint256 _lastRewardBlock, uint256 _accPantherPerShare, uint16 _depositFeeBP, uint256 _harvestInterval);
	function poolLength() external view returns (uint256 _poolLength);
	function userInfo(uint256 _pid, address _user) external view returns (uint256 _amount, uint256 _rewardDebt, uint256 _rewardLockedUp, uint256 _nextHarvestUntil);

	function deposit(uint256 _pid, uint256 _amount, address _referrer) external;
	function withdraw(uint256 _pid, uint256 _amount) external;
	function emergencyWithdraw(uint256 _pid) external;
}
