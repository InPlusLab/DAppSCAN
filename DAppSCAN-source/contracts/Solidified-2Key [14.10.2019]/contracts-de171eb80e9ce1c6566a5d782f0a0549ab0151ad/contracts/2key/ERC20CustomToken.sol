pragma solidity ^0.4.24;


import '../openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol';

contract ERC20CustomToken is StandardToken {
	constructor(string _name, string _symbol, uint8 _decimals, uint _totalSupply_) public {
		name = _name;
		symbol = _symbol;
		decimals = _decimals;
		totalSupply_ = _totalSupply_;
		balances[msg.sender] = totalSupply_;
	}
}
