pragma solidity ^0.5.2;

interface ITargetHandler {
	function setDispatcher (address _dispatcher) external;
	function deposit(uint256 _amountss) external returns (uint256); // token deposit
	function withdraw(uint256 _amounts) external returns (uint256);
	function withdrawProfit() external returns (uint256);
	function drainFunds() external returns (uint256);
	function getBalance() external view  returns (uint256);
	function getPrinciple() external view  returns (uint256);
	function getProfit() external view  returns (uint256);
	function getTargetAddress() external view  returns (address);
	function getToken() external view  returns (address);
	function getDispatcher() external view  returns (address);
}