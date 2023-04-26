// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Transfers } from "../contracts/modules/Transfers.sol";
import { Wrapping } from "../contracts/modules/Wrapping.sol";

import { Router02 } from "../contracts/interop/UniswapV2.sol";

import { $ } from "../contracts/network/$.sol";

contract Env
{
	using SafeMath for uint256;

	uint256 public initialBalance = 10 ether;

	receive() external payable {}

	// these addresses are hardcoded and dependent on the private key used on migration
	address constant EXCHANGE = 0x66bd90BdB4596482239C82C360fCFC4008b8dfc1;
	address constant CAKE_BUYBACK = 0xaC5d0E968583862386491332C228F8F4E5DA7AB2;
	address constant CAKE_COLLECTOR = 0x5BB74FBC6d92c1854104901f4690db1DF4004a24;
	address constant CAKE_STRATEGY = 0x8bA5251F3e122A9813D531a9c5b4fe962026E5E5;
	address constant AUTO_COLLECTOR = 0x9EA3DC7D521668aF962a3Cd50daA6Abc30CE8572;
	address constant AUTO_STRATEGY = 0xaca205e287EB55F385AFFFb4384e102442C08F6f;
	address constant PANTHER_BUYBACK = 0x82326930b531AF5c74DE2101e6dBa070e6F0Ce85;
	address constant PANTHER_STRATEGY = 0x002e3801cC6452dA0817bDD8598Ae0Bb190d27FD;

	function _getBalance(address _token) internal view returns (uint256 _amount)
	{
		return Transfers._getBalance(_token);
	}

	function _mint(address _token, uint256 _amount) internal
	{
		address _router = $.UniswapV2_Compatible_ROUTER02;
		address _TOKEN = Router02(_router).WETH();
		if (_token == _TOKEN) {
			Wrapping._wrap(_token, _amount);
		} else {
			address _this = address(this);
			uint256 _value = _this.balance;
			uint256 _deadline = uint256(-1);
			address[] memory _path = new address[](2);
			_path[0] = _TOKEN;
			_path[1] = _token;
			Router02(_router).swapETHForExactTokens{value: _value}(_amount, _path, _this, _deadline);
		}
	}

	function _burnAll(address _token) internal
	{
		_burn(_token, _getBalance(_token));
	}

	function _burn(address _token, uint256 _amount) internal
	{
		address _from = msg.sender;
		Transfers._pushFunds(_token, _from, _amount);
	}
}
