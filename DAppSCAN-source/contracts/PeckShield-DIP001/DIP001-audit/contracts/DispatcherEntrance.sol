pragma solidity 0.5.4;

import './DSLibrary/DSAuth.sol';
import './interface/IDispatcher.sol';

contract DispatcherEntrance is DSAuth {

	mapping(address => mapping(address => address)) dispatchers;

	function registDispatcher(address _fund, address _token, address _dispatcher) external auth {
		dispatchers[_fund][_token] = _dispatcher;
	}

	function getDispatcher(address _fund, address _token) public view returns (address) {
		return dispatchers[_fund][_token];
	}
}