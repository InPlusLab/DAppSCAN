// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { GCFormulae } from "./GCFormulae.sol";
import { GATokenBase } from "./GATokenBase.sol";
import { GADelegatedReserveManager } from "./GADelegatedReserveManager.sol";
import { G } from "./G.sol";
import { GA } from "./GA.sol";

/**
 * @notice This contract implements the functionality for the gaToken Type 2.
 *         As with all gaTokens, gaTokens Type 2 use an Aave aToken as
 *         reserve token. Furthermore, Type 2 tokens will use that aToken
 *         balance to borrow funds that are then deposited into another gToken.
 *         Periodically the gaToken Type 2 will collect profits from investing
 *         borrowed assets in the gToken. These profits are converted into the aToken
 *         underlying asset and incorporated to the reserve. See GATokenBase and
 *         GADelegatedReserveManager for further documentation.
 */
contract GATokenType2 is GATokenBase
{
	using GADelegatedReserveManager for GADelegatedReserveManager.Self;

	GADelegatedReserveManager.Self drm;

	/**
	 * @dev Constructor for the gaToken Type 2 contract.
	 * @param _name The ERC-20 token name.
	 * @param _symbol The ERC-20 token symbol.
	 * @param _decimals The ERC-20 token decimals.
	 * @param _stakesToken The ERC-20 token address to be used as stakes
	 *                     token (GRO).
	 * @param _reserveToken The ERC-20 token address to be used as reserve
	 *                      token (e.g. aLINK for gacLINK).
	 * @param _borrowToken The aToken used for borrowing funds on compound (aDAI).
	 * @param _growthToken The gToken used for reinvesting borrowed funds (gDAI).
	 */
	constructor (string memory _name, string memory _symbol, uint8 _decimals, address _stakesToken, address _reserveToken, address _borrowToken, address _growthToken)
		GATokenBase(_name, _symbol, _decimals, _stakesToken, _reserveToken, _growthToken) public
	{
		drm.init(_reserveToken, _borrowToken, _growthToken);
	}

	/**
	 * @notice Provides the total amount of the underlying asset (or equivalent)
	 *         this contract is currently borrowing on Aave.
	 * @return _borrowingReserveUnderlying The underlying asset borrowing
	 *                                     balance on Aave.
	 */
	function borrowingReserveUnderlying() public view override returns (uint256 _borrowingReserveUnderlying)
	{
		uint256 _lendAmount = GA.getLendAmount(reserveToken);
		uint256 _availableAmount = _lendAmount.mul(GA.getCollateralRatio(reserveToken)).div(1e18);
		uint256 _borrowAmount = GA.getBorrowAmount(drm.borrowToken);
		uint256 _freeAmount = GA.getLiquidityAmount(drm.borrowToken);
		uint256 _totalAmount = _borrowAmount.add(_freeAmount);
		return _totalAmount > 0 ? _availableAmount.mul(_borrowAmount).div(_totalAmount) : 0;
	}

	/**
	 * @notice Provides the contract address for the GExchange implementation
	 *         currently being used to convert the gToken reserve token (DAI),
	 *         into the underlying asset.
	 * @return _exchange A GExchange compatible contract address, or address(0)
	 *                   if it has not been set.
	 */
	function exchange() public view override returns (address _exchange)
	{
		return drm.exchange;
	}

	/**
	 * @notice Not revelant to gaTokens Type 2.
	 * @return _miningMinGulpAmount Always zero.
	 * @return _miningMaxGulpAmount Always zero.
	 */
	function miningGulpRange() public view override returns (uint256 _miningMinGulpAmount, uint256 _miningMaxGulpAmount)
	{
		return (0, 0);
	}

	/**
	 * @notice Provides the minimum and maximum amount of the gToken reserve
	 *         profit to be processed on every operation. If the profit balance
	 *         is below the minimum it waits until more accumulates.
	 *         If the total profit is beyond the maximum it processes the
	 *         maximum and leaves the rest for future operations. The profit
	 *         accumulated via gToken reinvestment is converted to the
	 *         underlying asset and used to mint the associated aToken.
	 *         This range is used to avoid wasting gas converting small
	 *         amounts as well as mitigating slipage converting large amounts.
	 * @return _growthMinGulpAmount The minimum profit of the gToken reserve
	 *                              to be processed per deposit/withdrawal.
	 * @return _growthMaxGulpAmount The maximum profit of the gToken reserve
	 *                              to be processed per deposit/withdrawal.
	 */
	function growthGulpRange() public view override returns (uint256 _growthMinGulpAmount, uint256 _growthMaxGulpAmount)
	{
		return (drm.growthMinGulpAmount, drm.growthMaxGulpAmount);
	}

	/**
	 * @notice Provides the target collateralization ratio and margin to be
	 *         maintained by this contract. The amount is relative to the
	 *         maximum collateralization available for the associated aToken
	 *         on Aave. gaToken Type 2 uses the reserve token as collateral
	 *         to borrow funds and revinvest into the gToken.
	 * @param _collateralizationRatio The percent value relative to the
	 *                                maximum allowed that this contract
	 *                                will target for collateralization
	 *                                (defaults to 66%)
	 * @param _collateralizationRatio The percent value relative to the
	 *                                maximum allowed that this contract
	 *                                will target for collateralization
	 *                                margin (defaults to 8%)
	 */
	function collateralizationRatio() public view override returns (uint256 _collateralizationRatio, uint256 _collateralizationMargin)
	{
		return (drm.collateralizationRatio, drm.collateralizationMargin);
	}

	/**
	 * @notice Sets the contract address for the GExchange implementation
	 *         to be used in converting the gToken reserve token (DAI) into
	 *         the underlying asset. This is a priviledged function
	 *         restricted to the contract owner.
	 * @param _exchange A GExchange compatible contract address.
	 */
	function setExchange(address _exchange) public override onlyOwner nonReentrant
	{
		drm.setExchange(_exchange);
	}

	/**
	 * @notice Not revelant to gaTokens Type 2.
	 * @param _miningMinGulpAmount Ignored.
	 * @param _miningMaxGulpAmount Ignored.
	 */
	function setMiningGulpRange(uint256 _miningMinGulpAmount, uint256 _miningMaxGulpAmount) public override /*onlyOwner nonReentrant*/
	{
		_miningMinGulpAmount; _miningMaxGulpAmount; // silences warnings
	}

	/**
	 * @notice Sets the minimum and maximum amount of the gToken reserve profit
	 *         to be processed on every operation. See growthGulpRange().
	 *         This is a priviledged function restricted to the contract owner.
	 * @param _growthMinGulpAmount The minimum profit of the gToken reserve
	 *                             to be processed per deposit/withdrawal.
	 * @param _growthMaxGulpAmount The maximum profit of the gToken reserve
	 *                             to be processed per deposit/withdrawal.
	 */
	function setGrowthGulpRange(uint256 _growthMinGulpAmount, uint256 _growthMaxGulpAmount) public override onlyOwner nonReentrant
	{
		drm.setGrowthGulpRange(_growthMinGulpAmount, _growthMaxGulpAmount);
	}

	/**
	 * @notice Sets the target collateralization ratio and margin to be
	 *         maintained by this contract. See collateralizationRatio().
	 *         Setting both parameters to 0 turns off collateralization.
	 *         This is a priviledged function restricted to the contract owner.
	 * @param _collateralizationRatio The percent value relative to the
	 *                                maximum allowed that this contract
	 *                                will target for collateralization
	 *                                (defaults to 66%)
	 * @param _collateralizationRatio The percent value relative to the
	 *                                maximum allowed that this contract
	 *                                will target for collateralization
	 *                                margin (defaults to 8%)
	 */
	function setCollateralizationRatio(uint256 _collateralizationRatio, uint256 _collateralizationMargin) public override onlyOwner nonReentrant
	{
		drm.setCollateralizationRatio(_collateralizationRatio, _collateralizationMargin);
	}

	/**
	 * @dev This method is overriden from GTokenBase and sets up the reserve
	 *      after a deposit comes along. It basically adjusts the
	 *      collateralization to reflect the new increased reserve
	 *      balance. This method uses the GADelegatedReserveManager to
	 *      adjust the reserve. See GADelegatedReserveManager.sol.
	 * @param _cost The amount of reserve being deposited (ignored).
	 * @return _success A boolean indicating whether or not the operation
	 *                  succeeded.
	 */
	function _prepareDeposit(uint256 _cost) internal override returns (bool _success)
	{
		_cost; // silences warnings
		return drm.adjustReserve(0);
	}

	/**
	 * @dev This method is overriden from GTokenBase and sets up the reserve
	 *      before a withdrawal comes along. It basically calculates the
	 *      the amount that will be left in the reserve, in terms of aToken
	 *      cost, and adjusts the collateralization accordingly. This
	 *      method uses the GADelegatedReserveManager to adjust the reserve.
	 *      See GADelegatedReserveManager.sol.
	 * @param _cost The amount of reserve being withdrawn and that needs to
	 *              be immediately liquid.
	 * @return _success A boolean indicating whether or not the operation succeeded.
	 *                  The operation may fail if it is not possible to recover
	 *                  the required liquidity (e.g. low liquidity in the markets).
	 */
	function _prepareWithdrawal(uint256 _cost) internal override returns (bool _success)
	{
		return drm.adjustReserve(GCFormulae._calcUnderlyingCostFromCost(_cost, GA.fetchExchangeRate(reserveToken)));
	}
}
