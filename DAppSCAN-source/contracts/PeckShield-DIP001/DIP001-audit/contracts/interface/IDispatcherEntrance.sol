pragma solidity ^0.5.2;

interface IDispatcherEntrance {
	function registDispatcher(address _fund, address _token, address _dispatcher) external;
	function getDispatcher(address _fund, address _token) external returns (address);
}