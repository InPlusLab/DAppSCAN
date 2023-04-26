pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;


interface ENSIntegration
{
	function setName(address ens, string calldata name) external;
}
