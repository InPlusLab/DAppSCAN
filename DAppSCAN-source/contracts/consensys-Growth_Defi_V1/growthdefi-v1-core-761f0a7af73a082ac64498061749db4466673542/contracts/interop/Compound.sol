// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Minimal set of declarations for Compound interoperability.
 */
interface Comptroller
{
	function oracle() external view returns (address _oracle);
	function enterMarkets(address[] calldata _ctokens) external returns (uint256[] memory _errorCodes);
	function markets(address _ctoken) external view returns (bool _isListed, uint256 _collateralFactorMantissa);
	function getAccountLiquidity(address _account) external view returns (uint256 _error, uint256 _liquidity, uint256 _shortfall);
}

interface CPriceOracle
{
	function getUnderlyingPrice(address _ctoken) external view returns (uint256 _price);
}

interface CToken is IERC20
{
	function underlying() external view returns (address _token);
	function exchangeRateStored() external view returns (uint256 _exchangeRate);
	function borrowBalanceStored(address _account) external view returns (uint256 _borrowBalance);
	function exchangeRateCurrent() external returns (uint256 _exchangeRate);
	function getCash() external view returns (uint256 _cash);
	function borrowBalanceCurrent(address _account) external returns (uint256 _borrowBalance);
	function balanceOfUnderlying(address _owner) external returns (uint256 _underlyingBalance);
	function mint() external payable;
	function mint(uint256 _mintAmount) external returns (uint256 _errorCode);
	function repayBorrow() external payable;
	function repayBorrow(uint256 _repayAmount) external returns (uint256 _errorCode);
	function redeemUnderlying(uint256 _redeemAmount) external returns (uint256 _errorCode);
	function borrow(uint256 _borrowAmount) external returns (uint256 _errorCode);
}
