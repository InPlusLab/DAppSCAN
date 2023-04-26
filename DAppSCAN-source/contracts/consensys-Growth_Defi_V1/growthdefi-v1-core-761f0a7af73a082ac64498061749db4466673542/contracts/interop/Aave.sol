// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Minimal set of declarations for Aave interoperability.
 */
interface LendingPoolAddressesProvider
{
	function getLendingPool() external view returns (address _pool);
	function getLendingPoolCore() external view returns (address payable _lendingPoolCore);
	function getPriceOracle() external view returns (address _priceOracle);
}

interface LendingPool
{
	function getReserveConfigurationData(address _reserve) external view returns (uint256 _ltv, uint256 _liquidationThreshold, uint256 _liquidationBonus, address _interestRateStrategyAddress, bool _usageAsCollateralEnabled, bool _borrowingEnabled, bool _stableBorrowRateEnabled, bool _isActive);
	function getUserAccountData(address _user) external view returns (uint256 _totalLiquidityETH, uint256 _totalCollateralETH, uint256 _totalBorrowsETH, uint256 _totalFeesETH, uint256 _availableBorrowsETH, uint256 _currentLiquidationThreshold, uint256 _ltv, uint256 _healthFactor);
	function getUserReserveData(address _reserve, address _user) external view returns (uint256 _currentATokenBalance, uint256 _currentBorrowBalance, uint256 _principalBorrowBalance, uint256 _borrowRateMode, uint256 _borrowRate, uint256 _liquidityRate, uint256 _originationFee, uint256 _variableBorrowIndex, uint256 _lastUpdateTimestamp, bool _usageAsCollateralEnabled);
	function deposit(address _reserve, uint256 _amount, uint16 _referralCode) external payable;
	function borrow(address _reserve, uint256 _amount, uint256 _interestRateMode, uint16 _referralCode) external;
	function repay(address _reserve, uint256 _amount, address payable _onBehalfOf) external payable;
	function flashLoan(address _receiver, address _reserve, uint256 _amount, bytes calldata _params) external;
}

interface LendingPoolCore
{
	function getReserveDecimals(address _reserve) external view returns (uint256 _decimals);
	function getReserveAvailableLiquidity(address _reserve) external view returns (uint256 _availableLiquidity);
}

interface AToken is IERC20
{
	function underlyingAssetAddress() external view returns (address _underlyingAssetAddress);
	function redeem(uint256 _amount) external;
}

interface APriceOracle
{
	function getAssetPrice(address _asset) external view returns (uint256 _assetPrice);
}

interface FlashLoanReceiver
{
	function executeOperation(address _reserve, uint256 _amount, uint256 _fee, bytes calldata _params) external;
}
