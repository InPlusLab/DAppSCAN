pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./IexecERC20Common.sol";
import "../DelegateBase.sol";
import "../interfaces/IexecERC20.sol";
import "../interfaces/IexecTokenSpender.sol";


contract IexecERC20Delegate is IexecERC20, DelegateBase, IexecERC20Common
{
	function transfer(address recipient, uint256 amount)
	external override returns (bool)
	{
			_transfer(_msgSender(), recipient, amount);
			return true;
	}

	function approve(address spender, uint256 value)
	external override returns (bool)
	{
			_approve(_msgSender(), spender, value);
			return true;
	}

	function approveAndCall(address spender, uint256 value, bytes calldata extraData)
	external override returns (bool)
	{
			_approve(_msgSender(), spender, value);
			require(IexecTokenSpender(spender).receiveApproval(_msgSender(), value, address(this), extraData), 'approval-refused');
			return true;
	}

	function transferFrom(address sender, address recipient, uint256 amount)
	external override returns (bool)
	{
			_transfer(sender, recipient, amount);
			_approve(sender, _msgSender(), m_allowances[sender][_msgSender()].sub(amount));
			return true;
	}

	function increaseAllowance(address spender, uint256 addedValue)
	external override returns (bool)
	{
			_approve(_msgSender(), spender, m_allowances[_msgSender()][spender].add(addedValue));
			return true;
	}


	function decreaseAllowance(address spender, uint256 subtractedValue)
	external override returns (bool)
	{
			_approve(_msgSender(), spender, m_allowances[_msgSender()][spender].sub(subtractedValue));
			return true;
	}
}
