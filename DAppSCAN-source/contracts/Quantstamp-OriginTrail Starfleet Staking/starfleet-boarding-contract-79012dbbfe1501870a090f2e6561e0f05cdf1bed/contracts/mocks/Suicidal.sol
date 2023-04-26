pragma solidity 0.6.10;
contract Suicidal {

	event EthReceived(uint256 value); 
	fallback () external payable {
		emit EthReceived(msg.value);
	}  
	function dieAndSendETH(address payable receiver) public { 
		selfdestruct(receiver); 
	}
}