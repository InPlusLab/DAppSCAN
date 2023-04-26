// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert, AssertAddress } from "truffle/Assert.sol";

import { Env } from "./Env.sol";

import { GCFormulae } from "../contracts/GCFormulae.sol";

import { AaveLendingMarketAbstraction } from "../contracts/modules/AaveLendingMarketAbstraction.sol";

contract TestAaveLendingMarketAbstraction is Env
{
	constructor () public
	{
		AaveLendingMarketAbstraction._safeEnter(aDAI);
	}

	function test01() public
	{
		AssertAddress.equal(AaveLendingMarketAbstraction._getUnderlyingToken(aDAI), DAI, "DAI must be the underlying of aDAI");
		AssertAddress.equal(AaveLendingMarketAbstraction._getUnderlyingToken(aUSDC), USDC, "USDC must be the underlying of aUSDC");
		AssertAddress.equal(AaveLendingMarketAbstraction._getUnderlyingToken(aETH), WETH, "WETH must be the underlying of aETH");
		AssertAddress.equal(AaveLendingMarketAbstraction._getUnderlyingToken(aWBTC), WBTC, "WBTC must be the underlying of aWBTC");
	}

	function test02() public
	{
		_burnAll(DAI);
		_burnAll(aDAI);
		_mint(DAI, 100e18);
		Assert.equal(_getBalance(DAI), 100e18, "DAI balance must be 100e18");
		Assert.equal(_getBalance(aDAI), 0e18, "aDAI balance must be 0e18");

		uint256 _exchangeRate = AaveLendingMarketAbstraction._fetchExchangeRate(aDAI);
		uint256 _amountaDAI = GCFormulae._calcCostFromUnderlyingCost(100e18, _exchangeRate);

		AaveLendingMarketAbstraction._safeLend(aDAI, 100e18);

		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");
		Assert.equal(_getBalance(aDAI), _amountaDAI, "aDAI balance must match");
		Assert.isAbove(AaveLendingMarketAbstraction._fetchLendAmount(aDAI), 99999e15, "DAI lend balance must be above 99999e15");
	}

	function test03() public
	{
		_burnAll(DAI);
		_burnAll(aDAI);
		_mint(aDAI, 500e18);
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");
		Assert.equal(_getBalance(aDAI), 500e18, "aDAI balance must be 500e18");

		uint256 _exchangeRate = AaveLendingMarketAbstraction._fetchExchangeRate(aDAI);
		uint256 _amountDAI = GCFormulae._calcUnderlyingCostFromCost(500e18, _exchangeRate);
		uint256 _amountaDAI = GCFormulae._calcCostFromUnderlyingCost(_amountDAI, _exchangeRate);

		Assert.equal(AaveLendingMarketAbstraction._fetchLendAmount(aDAI), _amountDAI, "DAI lend balance must match");

		AaveLendingMarketAbstraction._safeRedeem(aDAI, _amountDAI);

		Assert.equal(_getBalance(aDAI), uint256(500e18).sub(_amountaDAI), "aDAI balance must be consistent");
		Assert.equal(_getBalance(DAI), _amountDAI, "DAI balance must match");
	}

	function test04() public
	{
		_burnAll(DAI);
		_burnAll(aDAI);
		_burnAll(USDC);
		_burnAll(aUSDC);
		_mint(DAI, 100e18);
		Assert.equal(_getBalance(DAI), 100e18, "DAI balance must be 100e18");
		Assert.equal(_getBalance(aDAI), 0e18, "aDAI balance must be 0e18");
		Assert.equal(_getBalance(USDC), 0e6, "USDC balance must be 0e6");
		Assert.equal(_getBalance(aUSDC), 0e6, "aUSDC balance must be 0e6");

		uint256 _exchangeRate = AaveLendingMarketAbstraction._fetchExchangeRate(aDAI);
		uint256 _amountaDAI = GCFormulae._calcCostFromUnderlyingCost(100e18, _exchangeRate);

		AaveLendingMarketAbstraction._safeLend(aDAI, 100e18);

		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");
		Assert.equal(_getBalance(aDAI), _amountaDAI, "aDAI balance must match");
		Assert.equal(AaveLendingMarketAbstraction._fetchLendAmount(aDAI), 100e18, "DAI lend balance must be 100e18");

		AaveLendingMarketAbstraction._safeBorrow(aUSDC, 50e6);
		uint256 _borrowAmount = AaveLendingMarketAbstraction._fetchBorrowAmount(aUSDC);

		Assert.equal(_getBalance(USDC), 50e6, "USDC balance must be 50e6");
		Assert.equal(_getBalance(aUSDC), 0e6, "aUSDC balance must be 0e6");

		uint256 _borrowFeeAmount = _borrowAmount.sub(50e6);
		_mint(USDC, _borrowFeeAmount);
		AaveLendingMarketAbstraction._safeRepay(aUSDC, _borrowAmount);

		Assert.equal(_getBalance(USDC), 0e6, "USDC balance must be 0e6");
		Assert.equal(_getBalance(aUSDC), 0e8, "cUSDC balance must be 0e6");
		Assert.equal(AaveLendingMarketAbstraction._fetchBorrowAmount(aUSDC), 0e6, "USDC borrow balance must be 0e6");
		Assert.equal(AaveLendingMarketAbstraction._fetchLendAmount(aDAI), 100e18, "DAI lend balance must be 100e18");

		AaveLendingMarketAbstraction._safeRedeem(aDAI, 100e18);

		Assert.equal(_getBalance(DAI), 100e18, "DAI balance must be 100e18");
		Assert.equal(_getBalance(aDAI), 0e18, "cDAI balance must be 0e18");
		Assert.equal(AaveLendingMarketAbstraction._fetchLendAmount(aDAI), 0e18, "DAI lend balance must be 0e18");
	}

	function test05() public
	{
		AaveLendingMarketAbstraction._safeLend(aDAI, 0e18);
		AaveLendingMarketAbstraction._safeLend(aUSDC, 0e18);
		AaveLendingMarketAbstraction._safeLend(aETH, 0e18);
		AaveLendingMarketAbstraction._safeLend(aWBTC, 0e18);
	}

	function test06() public
	{
		AaveLendingMarketAbstraction._safeRedeem(aDAI, 0e18);
		AaveLendingMarketAbstraction._safeRedeem(aUSDC, 0e18);
		AaveLendingMarketAbstraction._safeRedeem(aETH, 0e18);
		AaveLendingMarketAbstraction._safeRedeem(aWBTC, 0e18);
	}

	function test07() public
	{
		AaveLendingMarketAbstraction._safeBorrow(aDAI, 0e8);
		AaveLendingMarketAbstraction._safeBorrow(aUSDC, 0e8);
		AaveLendingMarketAbstraction._safeBorrow(aETH, 0e8);
		AaveLendingMarketAbstraction._safeBorrow(aWBTC, 0e8);
	}

	function test08() public
	{
		AaveLendingMarketAbstraction._safeRepay(aDAI, 0e8);
		AaveLendingMarketAbstraction._safeRepay(aUSDC, 0e8);
		AaveLendingMarketAbstraction._safeRepay(aETH, 0e8);
		AaveLendingMarketAbstraction._safeRepay(aWBTC, 0e8);
	}

	function test09() public
	{
		_burnAll(DAI);
		_burnAll(aDAI);
		_mint(DAI, 100e18);

		Assert.equal(_getBalance(DAI), 100e18, "DAI balance must be 100e18");
		Assert.equal(_getBalance(aDAI), 0e18, "aDAI balance must be 0e18");

		AaveLendingMarketAbstraction._safeLend(aDAI, 100e18);

		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");

		AaveLendingMarketAbstraction._safeBorrow(aDAI, 70e18);

		Assert.equal(_getBalance(DAI), 70e18, "DAI balance must be 70e18");

		AaveLendingMarketAbstraction._safeLend(aDAI, 70e18);

		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");

		AaveLendingMarketAbstraction._safeBorrow(aDAI, 40e18);

		Assert.equal(_getBalance(DAI), 40e18, "DAI balance must be 40e18");

		uint256 _borrowAmount = AaveLendingMarketAbstraction._getBorrowAmount(aDAI);
		_mint(DAI, _borrowAmount.sub(40e18));

		Assert.isAtLeast(_getBalance(DAI), 110e18, "DAI balance must be at least 110e18");

		AaveLendingMarketAbstraction._safeRepay(aDAI, _borrowAmount);

		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");
		Assert.equal(AaveLendingMarketAbstraction._fetchBorrowAmount(aDAI), 0e18, "DAI borrow balance must be 0e18");

		uint256 _lendAmount = AaveLendingMarketAbstraction._getLendAmount(aDAI);
		Assert.isAtLeast(_lendAmount, 16999e16, "DAI balance must be at lest 16999e16");

		AaveLendingMarketAbstraction._safeRedeem(aDAI, _lendAmount);

		Assert.equal(_getBalance(DAI), _lendAmount, "DAI balance must match lend amount");
		Assert.equal(AaveLendingMarketAbstraction._fetchLendAmount(aDAI), 0e18, "DAI lend balance must be 0e18");
	}
/*
	function test10() public
	{
		_burnAll(WETH);
		_burnAll(aETH);
		_mint(WETH, 1e18);
		Assert.equal(_getBalance(WETH), 1e18, "WETH balance must be 1e18");
		Assert.equal(_getBalance(aETH), 0e18, "aETH balance must be 0e18");

		uint256 _exchangeRate = AaveLendingMarketAbstraction._fetchExchangeRate(aETH);
		uint256 _amountaETH = GCFormulae._calcCostFromUnderlyingCost(1e18, _exchangeRate);

		AaveLendingMarketAbstraction._safeLend(aETH, 1e18);

		Assert.equal(_getBalance(WETH), 0e18, "WETH balance must be 0e18");
		Assert.equal(_getBalance(aETH), _amountaETH, "aETH balance must match");
		Assert.isAbove(AaveLendingMarketAbstraction._fetchLendAmount(aETH), 999e15, "WETH lend balance must be above 999e15");
	}

	function test11() public
	{
		_burnAll(WETH);
		_burnAll(aETH);
		_mint(aETH, 25e8);
		Assert.equal(_getBalance(WETH), 0e18, "WETH balance must be 0e18");
		Assert.equal(_getBalance(aETH), 25e8, "aETH balance must be 25e8");

		uint256 _exchangeRate = AaveLendingMarketAbstraction._fetchExchangeRate(aETH);
		uint256 _amountETH = GCFormulae._calcUnderlyingCostFromCost(25e8, _exchangeRate);
		uint256 _amountaETH = GCFormulae._calcCostFromUnderlyingCost(_amountETH, _exchangeRate);

		AaveLendingMarketAbstraction._safeRedeem(cETH, _amountETH);

		Assert.equal(_getBalance(aETH), uint256(25e8).sub(_amountaETH), "aETH balance must be consistent");
		Assert.equal(_getBalance(WETH), _amountETH, "WETH balance must match");
	}

	function test12() public
	{
		_burnAll(WETH);
		_burnAll(aETH);
		_mint(WETH, 1e18);
		Assert.equal(_getBalance(WETH), 1e18, "WETH balance must be 1e18");
		Assert.equal(_getBalance(aETH), 0e18, "cETH balance must be 0e18");

		uint256 _exchangeRate = AaveLendingMarketAbstraction._fetchExchangeRate(aETH);
		uint256 _amountaETH = GCFormulae._calcCostFromUnderlyingCost(1e18, _exchangeRate);

		AaveLendingMarketAbstraction._safeLend(aETH, 1e18);

		Assert.equal(_getBalance(WETH), 0e18, "WETH balance must be 0e18");
		Assert.equal(_getBalance(aETH), _amountaETH, "aETH balance must match");
		Assert.isAbove(AaveLendingMarketAbstraction._fetchLendAmount(aETH), 999e15, "WETH lend balance must be above 999e15");

		AaveLendingMarketAbstraction._safeBorrow(aETH, 1e17);

		Assert.equal(_getBalance(WETH), 1e17, "WETH balance must be 1e17");
		Assert.equal(AaveLendingMarketAbstraction._fetchBorrowAmount(aETH), 1e17, "WETH borrow balance must be 1e17");

		AaveLendingMarketAbstraction._safeRepay(aETH, 1e17);

		Assert.equal(_getBalance(WETH), 0e18, "WETH balance must be 0e18");
		Assert.equal(AaveLendingMarketAbstraction._fetchBorrowAmount(aETH), 0e18, "WETH borrow balance must be 0e18");

		AaveLendingMarketAbstraction._safeRedeem(aETH, 1e18);

		Assert.equal(_getBalance(WETH), 1e18, "WETH balance must be 1e18");
		Assert.equal(_getBalance(aETH), 0e18, "cETH balance must be 0e18");
		Assert.equal(AaveLendingMarketAbstraction._fetchLendAmount(aETH), 0e18, "WETH lend balance must be 0e18");
	}
*/
}
