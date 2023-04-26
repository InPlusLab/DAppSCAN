pragma solidity ^0.6.0;

import '../Registry.sol';
import './Workerpool.sol';


contract WorkerpoolRegistry is Registry
{
	/**
	 * Constructor
	 */
	constructor()
	public Registry(
		address(new Workerpool()),
		"iExec Workerpool Registry (V5)",
		"iExecWorkerpoolV5")
	{
	}

	/**
	 * Pool creation
	 */
	function encodeInitializer(
		string memory _workerpoolDescription)
	internal pure returns (bytes memory)
	{
		return abi.encodeWithSignature(
			"initialize(string)",
			_workerpoolDescription
		);
	}

	function createWorkerpool(
		address          _workerpoolOwner,
		string  calldata _workerpoolDescription)
	external returns (Workerpool)
	{
		return Workerpool(_mintCreate(_workerpoolOwner, encodeInitializer(_workerpoolDescription)));
	}

	function predictWorkerpool(
		address          _workerpoolOwner,
		string  calldata _workerpoolDescription)
	external view returns (Workerpool)
	{
		return Workerpool(_mintPredict(_workerpoolOwner, encodeInitializer(_workerpoolDescription)));
	}
}
