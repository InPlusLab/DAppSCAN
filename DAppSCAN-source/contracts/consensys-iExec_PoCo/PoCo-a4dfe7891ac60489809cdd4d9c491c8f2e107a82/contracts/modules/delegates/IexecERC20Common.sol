pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../DelegateBase.sol";


contract IexecERC20Common is DelegateBase
{
	using SafeMathExtended for uint256;

	event Transfer(address indexed from, address indexed to, uint256 value);
	event Approval(address indexed owner, address indexed spender, uint256 value);

	function _transfer(address sender, address recipient, uint256 amount)
	internal
	{
			require(sender != address(0), "ERC20: transfer from the zero address");
			require(recipient != address(0), "ERC20: transfer to the zero address");

			m_balances[sender] = m_balances[sender].sub(amount);
			m_balances[recipient] = m_balances[recipient].add(amount);
			emit Transfer(sender, recipient, amount);
	}

	function _mint(address account, uint256 amount)
	internal
	{
			require(account != address(0), "ERC20: mint to the zero address");

			m_totalSupply = m_totalSupply.add(amount);
			m_balances[account] = m_balances[account].add(amount);
			emit Transfer(address(0), account, amount);
	}

	function _burn(address account, uint256 value)
	internal
	{
			require(account != address(0), "ERC20: burn from the zero address");

			m_totalSupply = m_totalSupply.sub(value);
			m_balances[account] = m_balances[account].sub(value);
			emit Transfer(account, address(0), value);
	}

	function _approve(address owner, address spender, uint256 value)
	internal
	{
			require(owner != address(0), "ERC20: approve from the zero address");
			require(spender != address(0), "ERC20: approve to the zero address");

			m_allowances[owner][spender] = value;
			emit Approval(owner, spender, value);
	}
}
