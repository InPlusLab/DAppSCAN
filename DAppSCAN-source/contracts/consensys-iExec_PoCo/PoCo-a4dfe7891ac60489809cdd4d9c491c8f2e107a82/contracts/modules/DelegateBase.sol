pragma solidity ^0.6.0;

import "../Store.sol";


abstract contract DelegateBase is Store
{
	constructor()
	internal
	{
		renounceOwnership();
	}

	modifier onlyScheduler(bytes32 _taskid)
	{
		require(_msgSender() == m_deals[m_tasks[_taskid].dealid].workerpool.owner);
		_;
	}
}
