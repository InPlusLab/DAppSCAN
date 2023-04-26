// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { CompoundLendingMarketAbstraction } from "./modules/CompoundLendingMarketAbstraction.sol";

/**
 * @dev This public library provides a single entrypoint to the Compound lending
 *      market internal library available in the modules folder. It is a
 *      complement to the G.sol library. Both libraries exists to circunvent the
 *      contract size limitation imposed by the EVM. See G.sol for further
 *      documentation.
 */
library GC
{
	function getUnderlyingToken(address _ctoken) public view returns (address _token) { return CompoundLendingMarketAbstraction._getUnderlyingToken(_ctoken); }
	function getCollateralRatio(address _ctoken) public view returns (uint256 _collateralFactor) { return CompoundLendingMarketAbstraction._getCollateralRatio(_ctoken); }
	function getMarketAmount(address _ctoken) public view returns (uint256 _marketAmount) { return CompoundLendingMarketAbstraction._getMarketAmount(_ctoken); }
	function getLiquidityAmount(address _ctoken) public view returns (uint256 _liquidityAmount) { return CompoundLendingMarketAbstraction._getLiquidityAmount(_ctoken); }
//	function getAvailableAmount(address _ctoken, uint256 _marginAmount) public view returns (uint256 _availableAmount) { return CompoundLendingMarketAbstraction._getAvailableAmount(_ctoken, _marginAmount); }
	function getExchangeRate(address _ctoken) public view returns (uint256 _exchangeRate) { return CompoundLendingMarketAbstraction._getExchangeRate(_ctoken); }
	function fetchExchangeRate(address _ctoken) public returns (uint256 _exchangeRate) { return CompoundLendingMarketAbstraction._fetchExchangeRate(_ctoken); }
	function getLendAmount(address _ctoken) public view returns (uint256 _amount) { return CompoundLendingMarketAbstraction._getLendAmount(_ctoken); }
	function fetchLendAmount(address _ctoken) public returns (uint256 _amount) { return CompoundLendingMarketAbstraction._fetchLendAmount(_ctoken); }
	function getBorrowAmount(address _ctoken) public view returns (uint256 _amount) { return CompoundLendingMarketAbstraction._getBorrowAmount(_ctoken); }
	function fetchBorrowAmount(address _ctoken) public returns (uint256 _amount) { return CompoundLendingMarketAbstraction._fetchBorrowAmount(_ctoken); }
//	function enter(address _ctoken) public returns (bool _success) { return CompoundLendingMarketAbstraction._enter(_ctoken); }
	function lend(address _ctoken, uint256 _amount) public returns (bool _success) { return CompoundLendingMarketAbstraction._lend(_ctoken, _amount); }
	function redeem(address _ctoken, uint256 _amount) public returns (bool _success) { return CompoundLendingMarketAbstraction._redeem(_ctoken, _amount); }
	function borrow(address _ctoken, uint256 _amount) public returns (bool _success) { return CompoundLendingMarketAbstraction._borrow(_ctoken, _amount); }
	function repay(address _ctoken, uint256 _amount) public returns (bool _success) { return CompoundLendingMarketAbstraction._repay(_ctoken, _amount); }
	function safeEnter(address _ctoken) public { CompoundLendingMarketAbstraction._safeEnter(_ctoken); }
	function safeLend(address _ctoken, uint256 _amount) public { CompoundLendingMarketAbstraction._safeLend(_ctoken, _amount); }
	function safeRedeem(address _ctoken, uint256 _amount) public { CompoundLendingMarketAbstraction._safeRedeem(_ctoken, _amount); }
//	function safeBorrow(address _ctoken, uint256 _amount) public { CompoundLendingMarketAbstraction._safeBorrow(_ctoken, _amount); }
//	function safeRepay(address _ctoken, uint256 _amount) public { CompoundLendingMarketAbstraction._safeRepay(_ctoken, _amount); }
}
