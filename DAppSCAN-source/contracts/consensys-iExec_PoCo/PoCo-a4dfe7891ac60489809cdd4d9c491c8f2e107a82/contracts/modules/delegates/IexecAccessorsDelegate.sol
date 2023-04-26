pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../DelegateBase.sol";
import "../interfaces/IexecAccessors.sol";


contract IexecAccessorsDelegate is IexecAccessors, DelegateBase
{

	function name()
	external view override returns (string memory)
	{
		return m_name;
	}

	function symbol()
	external view override returns (string memory)
	{
		return m_symbol;
	}

	function decimals()
	external view override returns (uint8)
	{
		return m_decimals;
	}

	function totalSupply()
	external view override returns (uint256)
	{
		return m_totalSupply;
	}

	function balanceOf(address account)
	external view override returns (uint256)
	{
		return m_balances[account];
	}

	function frozenOf(address account)
	external view override returns (uint256)
	{
		return m_frozens[account];
	}

	function allowance(address account, address spender)
	external view override returns (uint256)
	{
		return m_allowances[account][spender];
	}

	function viewAccount(address account)
	external view override returns (IexecLibCore_v5.Account memory)
	{
		return IexecLibCore_v5.Account(m_balances[account], m_frozens[account]);
	}

	function token()
	external view override returns (address)
	{
		return address(m_baseToken);
	}

	function viewDeal(bytes32 _id)
	external view override returns (IexecLibCore_v5.Deal memory deal)
	{
		return m_deals[_id];
	}

	function viewConsumed(bytes32 _id)
	external view override returns (uint256 consumed)
	{
		return m_consumed[_id];
	}

	function viewPresigned(bytes32 _id)
	external view override returns (address signer)
	{
		return m_presigned[_id];
	}

	function viewTask(bytes32 _taskid)
	external view override returns (IexecLibCore_v5.Task memory)
	{
		return m_tasks[_taskid];
	}

	function viewContribution(bytes32 _taskid, address _worker)
	external view override returns (IexecLibCore_v5.Contribution memory)
	{
		return m_contributions[_taskid][_worker];
	}

	function viewScore(address _worker)
	external view override returns (uint256)
	{
		return m_workerScores[_worker];
	}

	function resultFor(bytes32 id)
	external view override returns (bytes memory)
	{
		IexecLibCore_v5.Task storage task = m_tasks[id];
		require(task.status == IexecLibCore_v5.TaskStatusEnum.COMPLETED);
		return task.results;
	}

	function viewCategory(uint256 _catid)
	external view override returns (IexecLibCore_v5.Category memory category)
	{
		return m_categories[_catid];
	}

	function countCategory()
	external view override returns (uint256 count)
	{
		return m_categories.length;
	}


	function appregistry()
	external view override returns (IRegistry)
	{
		return m_appregistry;
	}

	function datasetregistry()
	external view override returns (IRegistry)
	{
		return m_datasetregistry;
	}

	function workerpoolregistry()
	external view override returns (IRegistry)
	{
		return m_workerpoolregistry;
	}

	function teebroker()
	external view override returns (address)
	{
		return m_teebroker;
	}

	function callbackgas()
	external view override returns (uint256)
	{
		return m_callbackgas;
	}

	function contribution_deadline_ratio()
	external view override returns (uint256)
	{
		return CONTRIBUTION_DEADLINE_RATIO;
	}

	function reveal_deadline_ratio()
	external view override returns (uint256)
	{
		return REVEAL_DEADLINE_RATIO;
	}

	function final_deadline_ratio()
	external view override returns (uint256)
	{
		return FINAL_DEADLINE_RATIO;
	}

	function workerpool_stake_ratio()
	external view override returns (uint256)
	{
		return WORKERPOOL_STAKE_RATIO;
	}

	function kitty_ratio()
	external view override returns (uint256)
	{
		return KITTY_RATIO;
	}

	function kitty_min()
	external view override returns (uint256)
	{
		return KITTY_MIN;
	}

	function kitty_address()
	external view override returns (address)
	{
		return KITTY_ADDRESS;
	}

	function groupmember_purpose()
	external view override returns (uint256)
	{
		return GROUPMEMBER_PURPOSE;
	}

	function eip712domain_separator()
	external view override returns (bytes32)
	{
		return EIP712DOMAIN_SEPARATOR;
	}
}
