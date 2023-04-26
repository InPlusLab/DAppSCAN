pragma solidity ^0.6.0;

import "../RegistryEntry.sol";


contract Workerpool is RegistryEntry
{
	/**
	 * Parameters
	 */
	string  public m_workerpoolDescription;
	uint256 public m_workerStakeRatioPolicy;     // % of reward to stake
	uint256 public m_schedulerRewardRatioPolicy; // % of reward given to scheduler

	/**
	 * Events
	 */
	event PolicyUpdate(
		uint256 oldWorkerStakeRatioPolicy,     uint256 newWorkerStakeRatioPolicy,
		uint256 oldSchedulerRewardRatioPolicy, uint256 newSchedulerRewardRatioPolicy);

	/**
	 * Constructor
	 */
	function initialize(
		string memory _workerpoolDescription)
	public
	{
		_initialize(msg.sender);
		m_workerpoolDescription      = _workerpoolDescription;
		m_workerStakeRatioPolicy     = 30; // mutable
		m_schedulerRewardRatioPolicy = 1;  // mutable
	}

	function changePolicy(
		uint256 _newWorkerStakeRatioPolicy,
		uint256 _newSchedulerRewardRatioPolicy)
	external onlyOwner()
	{
		require(_newSchedulerRewardRatioPolicy <= 100);

		emit PolicyUpdate(
			m_workerStakeRatioPolicy,     _newWorkerStakeRatioPolicy,
			m_schedulerRewardRatioPolicy, _newSchedulerRewardRatioPolicy
		);

		m_workerStakeRatioPolicy     = _newWorkerStakeRatioPolicy;
		m_schedulerRewardRatioPolicy = _newSchedulerRewardRatioPolicy;
	}
}
