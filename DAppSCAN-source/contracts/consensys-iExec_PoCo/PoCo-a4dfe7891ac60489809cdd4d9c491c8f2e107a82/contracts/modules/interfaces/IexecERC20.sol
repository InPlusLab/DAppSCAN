pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;


interface IexecERC20
{
	event Transfer(address indexed from, address indexed to, uint256 value);
	event Approval(address indexed owner, address indexed spender, uint256 value);

	function transfer(address,uint256) external returns (bool);
	function approve(address,uint256) external returns (bool);
	function transferFrom(address,address,uint256) external returns (bool);
	function increaseAllowance(address,uint256) external returns (bool);
	function decreaseAllowance(address,uint256) external returns (bool);
	function approveAndCall(address,uint256,bytes calldata) external returns (bool);
}
