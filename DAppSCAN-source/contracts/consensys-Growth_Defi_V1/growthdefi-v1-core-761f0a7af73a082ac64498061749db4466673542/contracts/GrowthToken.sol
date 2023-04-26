// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @dev The definitions of this file are provided for reference only.
 *      The GRO token has been published independently.
 */
interface ERC20Interface
{
	function totalSupply() external view returns (uint);
	function balanceOf(address tokenOwner) external view returns (uint balance);
	function allowance(address tokenOwner, address spender) external view returns (uint remaining);
	function transfer(address to, uint tokens) external returns (bool success);
	function approve(address spender, uint tokens) external returns (bool success);
	function transferFrom(address from, address to, uint tokens) external returns (bool success);

	event Transfer(address indexed from, address indexed to, uint tokens);
	event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}

contract SafeMath_
{
	function safeAdd(uint a, uint b) public pure returns (uint c)
	{
		c = a + b;
		require(c >= a);
	}

	function safeSub(uint a, uint b) public pure returns (uint c)
	{
		require(b <= a);
		c = a - b;
	}

	function safeMul(uint a, uint b) public pure returns (uint c)
	{
		c = a * b;
		require(a == 0 || c / a == b);
	}

	function safeDiv(uint a, uint b) public pure returns (uint c) {
		require(b > 0);
		c = a / b;
	}
}

contract GrowthToken is ERC20Interface, SafeMath_
{
	string public name;
	string public symbol;
	uint8 public decimals; 

	uint256 public _totalSupply;

	mapping (address => uint) balances;
	mapping (address => mapping (address => uint)) allowed;

	constructor () public
	{
		name = "Growth";
		symbol = "GRO";
		decimals = 18;
		_totalSupply = 1000000000000000000000000;
		balances[msg.sender] = _totalSupply;
		emit Transfer(address(0), msg.sender, _totalSupply);
	}

	function totalSupply() override public view returns (uint)
	{
		return _totalSupply - balances[address(0)];
	}

	function balanceOf(address tokenOwner) override public view returns (uint balance)
	{
		return balances[tokenOwner];
	}

	function allowance(address tokenOwner, address spender) override public view returns (uint remaining)
	{
		return allowed[tokenOwner][spender];
	}

	function approve(address spender, uint tokens) override public returns (bool success)
	{
		allowed[msg.sender][spender] = tokens;
		emit Approval(msg.sender, spender, tokens);
		return true;
	}

	function transfer(address to, uint tokens) override public returns (bool success)
	{
		balances[msg.sender] = safeSub(balances[msg.sender], tokens);
		balances[to] = safeAdd(balances[to], tokens);
		emit Transfer(msg.sender, to, tokens);
		return true;
	}

	function transferFrom(address from, address to, uint tokens) override public returns (bool success)
	{
		balances[from] = safeSub(balances[from], tokens);
		allowed[from][msg.sender] = safeSub(allowed[from][msg.sender], tokens);
		balances[to] = safeAdd(balances[to], tokens);
		emit Transfer(from, to, tokens);
		return true;
	}
}
