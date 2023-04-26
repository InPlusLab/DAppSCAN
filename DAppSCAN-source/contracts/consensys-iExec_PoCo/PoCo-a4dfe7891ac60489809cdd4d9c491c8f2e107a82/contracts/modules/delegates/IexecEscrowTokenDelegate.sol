pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./IexecERC20Common.sol";
import "../DelegateBase.sol";
import "../interfaces/IexecEscrowToken.sol";
import "../interfaces/IexecTokenSpender.sol";


contract IexecEscrowTokenDelegate is IexecEscrowToken, IexecTokenSpender, DelegateBase, IexecERC20Common
{
	using SafeMathExtended for uint256;

	/***************************************************************************
	 *                         Escrow methods: public                          *
	 ***************************************************************************/
	receive()
	external override payable
	{
		revert("fallback-disabled");
	}

	function deposit(uint256 amount)
	external override returns (bool)
	{
		_deposit(_msgSender(), amount);
		_mint(_msgSender(), amount);
		return true;
	}

	function depositFor(uint256 amount, address target)
	external override returns (bool)
	{
		_deposit(_msgSender(), amount);
		_mint(target, amount);
		return true;
	}

	function depositForArray(uint256[] calldata amounts, address[] calldata targets)
	external override returns (bool)
	{
		require(amounts.length == targets.length);
		for (uint i = 0; i < amounts.length; ++i)
		{
			_deposit(_msgSender(), amounts[i]);
			_mint(targets[i], amounts[i]);
		}
		return true;
	}

	function withdraw(uint256 amount)
	external override returns (bool)
	{
		_burn(_msgSender(), amount);
		_withdraw(_msgSender(), amount);
		return true;
	}

	function recover()
	external override onlyOwner returns (uint256)
	{
		uint256 delta = m_baseToken.balanceOf(address(this)).sub(m_totalSupply);
		_mint(owner(), delta);
		return delta;
	}

	// Token Spender (endpoint for approveAndCallback calls to the proxy)
	function receiveApproval(address sender, uint256 amount, address token, bytes calldata)
	external override returns (bool)
	{
		require(token == address(m_baseToken), 'wrong-token');
		_deposit(sender, amount);
		_mint(sender, amount);
		return true;
	}

	function _deposit(address from, uint256 amount)
	internal
	{
		require(m_baseToken.transferFrom(from, address(this), amount));
	}

	function _withdraw(address to, uint256 amount)
	internal
	{
		m_baseToken.transfer(to, amount);
	}
}
