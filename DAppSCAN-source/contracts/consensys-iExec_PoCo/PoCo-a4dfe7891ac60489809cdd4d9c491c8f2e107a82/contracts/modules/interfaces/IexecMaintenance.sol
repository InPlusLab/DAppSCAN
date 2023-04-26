pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../../libs/IexecLibOrders_v5.sol";


interface IexecMaintenance
{
	function configure(address,string calldata,string calldata,uint8,address,address,address,address) external;
	function domain() external view returns (IexecLibOrders_v5.EIP712Domain memory);
	function updateDomainSeparator() external;
	function importScore(address) external;
	function setTeeBroker(address) external;
	function setCallbackGas(uint256) external;
}
