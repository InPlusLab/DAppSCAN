// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { AaveLendingMarketAbstraction } from "./modules/AaveLendingMarketAbstraction.sol";

/**
 * @dev This public library provides a single entrypoint to the Aave lending
 *      market internal library available in the modules folder. It is a
 *      complement to the G.sol library. Both libraries exists to circunvent the
 *      contract size limitation imposed by the EVM. See G.sol for further
 *      documentation.
 */
library GA
{
	function getUnderlyingToken(address _atoken) public view returns (address _token) { return AaveLendingMarketAbstraction._getUnderlyingToken(_atoken); }
	function getCollateralRatio(address _atoken) public view returns (uint256 _collateralFactor) { return AaveLendingMarketAbstraction._getCollateralRatio(_atoken); }
	function getMarketAmount(address _atoken) public view returns (uint256 _marketAmount) { return AaveLendingMarketAbstraction._getMarketAmount(_atoken); }
	function getLiquidityAmount(address _atoken) public view returns (uint256 _liquidityAmount) { return AaveLendingMarketAbstraction._getLiquidityAmount(_atoken); }
//	function getAvailableAmount(address _atoken, uint256 _marginAmount) public view returns (uint256 _availableAmount) { return AaveLendingMarketAbstraction._getAvailableAmount(_atoken, _marginAmount); }
	function getExchangeRate(address _atoken) public pure returns (uint256 _exchangeRate) { return AaveLendingMarketAbstraction._getExchangeRate(_atoken); }
	function fetchExchangeRate(address _atoken) public pure returns (uint256 _exchangeRate) { return AaveLendingMarketAbstraction._fetchExchangeRate(_atoken); }
	function getLendAmount(address _atoken) public view returns (uint256 _amount) { return AaveLendingMarketAbstraction._getLendAmount(_atoken); }
	function fetchLendAmount(address _atoken) public view returns (uint256 _amount) { return AaveLendingMarketAbstraction._fetchLendAmount(_atoken); }
	function getBorrowAmount(address _atoken) public view returns (uint256 _amount) { return AaveLendingMarketAbstraction._getBorrowAmount(_atoken); }
	function fetchBorrowAmount(address _atoken) public view returns (uint256 _amount) { return AaveLendingMarketAbstraction._fetchBorrowAmount(_atoken); }
//	function enter(address _atoken) public returns (bool _success) { return AaveLendingMarketAbstraction._enter(_atoken); }
	function lend(address _atoken, uint256 _amount) public returns (bool _success) { return AaveLendingMarketAbstraction._lend(_atoken, _amount); }
//	function redeem(address _atoken, uint256 _amount) public returns (bool _success) { return AaveLendingMarketAbstraction._redeem(_atoken, _amount); }
	function borrow(address _atoken, uint256 _amount) public returns (bool _success) { return AaveLendingMarketAbstraction._borrow(_atoken, _amount); }
	function repay(address _atoken, uint256 _amount) public returns (bool _success) { return AaveLendingMarketAbstraction._repay(_atoken, _amount); }
	function safeEnter(address _atoken) public pure { AaveLendingMarketAbstraction._safeEnter(_atoken); }
	function safeLend(address _atoken, uint256 _amount) public { AaveLendingMarketAbstraction._safeLend(_atoken, _amount); }
	function safeRedeem(address _atoken, uint256 _amount) public { AaveLendingMarketAbstraction._safeRedeem(_atoken, _amount); }
//	function safeBorrow(address _atoken, uint256 _amount) public { AaveLendingMarketAbstraction._safeBorrow(_atoken, _amount); }
//	function safeRepay(address _atoken, uint256 _amount) public { AaveLendingMarketAbstraction._safeRepay(_atoken, _amount); }
}
