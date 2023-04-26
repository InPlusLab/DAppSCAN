pragma solidity^0.4.0;

import "./DLL.sol";

contract TestDLL {

	using DLL for DLL.Data;
	DLL.Data dll;

	function isEmpty() public view returns (bool) {
		return dll.isEmpty();
	}
	
	function contains(uint _curr) public view returns (bool) {
		return dll.contains(_curr);
	}

	function getNext(uint _curr) public view returns (uint) {
		return dll.getNext(_curr);
	}
	
	function getPrev(uint _curr) public view returns (uint) {
		return dll.getPrev(_curr);
	}
	
	function getStart() public view returns (uint) {
		return dll.getStart();
	}
	
	function getEnd() public view returns (uint) {
		return dll.getEnd();
	}

	function insert(uint _prev, uint _curr, uint _next) public {
		dll.insert(_prev, _curr, _next);
	}

	function remove(uint _curr) public {
		dll.remove(_curr);
	}
}
