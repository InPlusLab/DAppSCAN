pragma solidity ^0.6.0;

import '../Registry.sol';
import './Dataset.sol';


contract DatasetRegistry is Registry
{
	/**
	 * Constructor
	 */
	constructor()
	public Registry(
		address(new Dataset()),
		"iExec Dataset Registry (V5)",
		"iExecDatasetsV5")
	{
	}

	/**
	 * Dataset creation
	 */
	function encodeInitializer(
		string  memory _datasetName,
		bytes   memory _datasetMultiaddr,
		bytes32        _datasetChecksum)
	internal pure returns (bytes memory)
	{
		return abi.encodeWithSignature(
			"initialize(string,bytes,bytes32)",
			_datasetName,
			_datasetMultiaddr,
			_datasetChecksum
		);
	}

	function createDataset(
		address          _datasetOwner,
		string  calldata _datasetName,
		bytes   calldata _datasetMultiaddr,
		bytes32          _datasetChecksum)
	external returns (Dataset)
	{
		return Dataset(_mintCreate(_datasetOwner, encodeInitializer(_datasetName, _datasetMultiaddr, _datasetChecksum)));
	}

	function predictDataset(
		address          _datasetOwner,
		string  calldata _datasetName,
		bytes   calldata _datasetMultiaddr,
		bytes32          _datasetChecksum)
	external view returns (Dataset)
	{
		return Dataset(_mintPredict(_datasetOwner, encodeInitializer(_datasetName, _datasetMultiaddr, _datasetChecksum)));
	}
}
