pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./IexecERC20Common.sol";
import "../DelegateBase.sol";
import "../interfaces/IexecEscrowNative.sol";


contract IexecEscrowNativeDelegate is IexecEscrowNative, DelegateBase, IexecERC20Common
{
	using SafeMathExtended for uint256;

	uint256 internal constant nRLCtoWei = 10 ** 9;
	/***************************************************************************
	 *                         Escrow methods: public                          *
	 ***************************************************************************/
	receive()
	external override payable
	{
		_deposit(_msgSender());
	}

	function deposit()
	external override payable returns (bool)
	{
		_deposit(_msgSender());
		return true;
	}

	function depositFor(address target)
	external override payable returns (bool)
	{
		_deposit(target);
		return true;
	}

	function depositForArray(uint256[] calldata amounts, address[] calldata targets)
	external override payable returns (bool)
	{
		require(amounts.length == targets.length);
		uint256 remaining = msg.value;
		for (uint i = 0; i < amounts.length; ++i)
		{
			_mint(targets[i], amounts[i]);
			remaining = remaining.sub(amounts[i].mul(nRLCtoWei));
		}
		_withdraw(_msgSender(), remaining);
		return true;
	}

	function withdraw(uint256 amount)
	external override returns (bool)
	{
		_burn(_msgSender(), amount);
		_withdraw(_msgSender(), amount.mul(nRLCtoWei));
		return true;
	}

	function recover()
	external override onlyOwner returns (uint256)
	{
		uint256 delta = address(this).balance.div(nRLCtoWei).sub(m_totalSupply);
		_mint(owner(), delta);
		return delta;
	}

	function _deposit(address target)
		internal
	{
		_mint(target, msg.value.div(nRLCtoWei));
		_withdraw(_msgSender(), msg.value.mod(nRLCtoWei));
	}

	function _withdraw(address to, uint256 value)
		internal
	{
		(bool success, ) = to.call.value(value)('');
		require(success, 'native-transfer-failled');
	}
}
