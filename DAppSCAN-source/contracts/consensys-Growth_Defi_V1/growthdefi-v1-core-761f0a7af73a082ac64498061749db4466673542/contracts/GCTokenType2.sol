// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { GCFormulae } from "./GCFormulae.sol";
import { GCTokenBase } from "./GCTokenBase.sol";
import { GCDelegatedReserveManager } from "./GCDelegatedReserveManager.sol";
import { G } from "./G.sol";
import { GC } from "./GC.sol";

/**
 * @notice This contract implements the functionality for the gcToken Type 2.
 *         As with all gcTokens, gcTokens Type 2 use a Compound cToken as
 *         reserve token. Furthermore, Type 2 tokens will use that cToken
 *         balance to borrow funds that are then deposited into another gToken.
 *         Periodically the gcToken Type 2 will collect profits from liquidity
 *         mining COMP, as well as profits from investing borrowed assets in
 *         the gToken. These profits are converted into the cToken underlying 
 *         asset and incorporated to the reserve. See GCTokenBase and
 *         GCDelegatedReserveManager for further documentation.
 */
contract GCTokenType2 is GCTokenBase
{
	using GCDelegatedReserveManager for GCDelegatedReserveManager.Self;

	GCDelegatedReserveManager.Self drm;

	/**
	 * @dev Constructor for the gcToken Type 2 contract.
	 * @param _name The ERC-20 token name.
	 * @param _symbol The ERC-20 token symbol.
	 * @param _decimals The ERC-20 token decimals.
	 * @param _stakesToken The ERC-20 token address to be used as stakes
	 *                     token (GRO).
	 * @param _reserveToken The ERC-20 token address to be used as reserve
	 *                      token (e.g. cDAI for gcDAI).
	 * @param _miningToken The ERC-20 token used for liquidity mining on
	 *                     compound (COMP).
	 * @param _borrowToken The cToken used for borrowing funds on compound (cDAI).
	 * @param _growthToken The gToken used for reinvesting borrowed funds (gDAI).
	 */
	constructor (string memory _name, string memory _symbol, uint8 _decimals, address _stakesToken, address _reserveToken, address _miningToken, address _borrowToken, address _growthToken)
		GCTokenBase(_name, _symbol, _decimals, _stakesToken, _reserveToken, _miningToken, _growthToken) public
	{
		drm.init(_reserveToken, _miningToken, _borrowToken, _growthToken);
	}

	/**
	 * @notice Provides the total amount of the underlying asset (or equivalent)
	 *         this contract is currently borrowing on Compound.
	 * @return _borrowingReserveUnderlying The underlying asset borrowing
	 *                                     balance on Compound.
	 */
	function borrowingReserveUnderlying() public view override returns (uint256 _borrowingReserveUnderlying)
	{
		uint256 _lendAmount = GC.getLendAmount(reserveToken);
		uint256 _availableAmount = _lendAmount.mul(GC.getCollateralRatio(reserveToken)).div(1e18);
		uint256 _borrowAmount = GC.getBorrowAmount(drm.borrowToken);
		uint256 _freeAmount = GC.getLiquidityAmount(drm.borrowToken);
		uint256 _totalAmount = _borrowAmount.add(_freeAmount);
		return _totalAmount > 0 ? _availableAmount.mul(_borrowAmount).div(_totalAmount) : 0;
	}

	/**
	 * @notice Provides the contract address for the GExchange implementation
	 *         currently being used to convert the mining token (COMP), and
	 *         the gToken reserve token (DAI), into the underlying asset.
	 * @return _exchange A GExchange compatible contract address, or address(0)
	 *                   if it has not been set.
	 */
	function exchange() public view override returns (address _exchange)
	{
		return drm.exchange;
	}

	/**
	 * @notice Provides the minimum and maximum amount of the mining token to
	 *         be processed on every operation. If the contract balance
	 *         is below the minimum it waits until more accumulates.
	 *         If the total amount is beyond the maximum it processes the
	 *         maximum and leaves the rest for future operations. The mining
	 *         token accumulated via liquidity mining is converted to the
	 *         underlying asset and used to mint the associated cToken.
	 *         This range is used to avoid wasting gas converting small
	 *         amounts as well as mitigating slipage converting large amounts.
	 * @return _miningMinGulpAmount The minimum amount of the mining token
	 *                              to be processed per deposit/withdrawal.
	 * @return _miningMaxGulpAmount The maximum amount of the mining token
	 *                              to be processed per deposit/withdrawal.
	 */
	function miningGulpRange() public view override returns (uint256 _miningMinGulpAmount, uint256 _miningMaxGulpAmount)
	{
		return (drm.miningMinGulpAmount, drm.miningMaxGulpAmount);
	}

	/**
	 * @notice Provides the minimum and maximum amount of the gToken reserve
	 *         profit to be processed on every operation. If the profit balance
	 *         is below the minimum it waits until more accumulates.
	 *         If the total profit is beyond the maximum it processes the
	 *         maximum and leaves the rest for future operations. The profit
	 *         accumulated via gToken reinvestment is converted to the
	 *         underlying asset and used to mint the associated cToken.
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
	 *         maximum collateralization available for the associated cToken
	 *         on Compound. gcToken Type 2 uses the reserve token as collateral
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
	 *         to be used in converting the mining token (COMP), and
	 *         the gToken reserve token (DAI), into the underlying asset.
	 *         This is a priviledged function restricted to the contract owner.
	 * @param _exchange A GExchange compatible contract address.
	 */
	function setExchange(address _exchange) public override onlyOwner nonReentrant
	{
		drm.setExchange(_exchange);
	}

	/**
	 * @notice Sets the minimum and maximum amount of the mining token to
	 *         be processed on every operation. See miningGulpRange().
	 *         This is a priviledged function restricted to the contract owner.
	 * @param _miningMinGulpAmount The minimum amount of the mining token
	 *                             to be processed per deposit/withdrawal.
	 * @param _miningMaxGulpAmount The maximum amount of the mining token
	 *                             to be processed per deposit/withdrawal.
	 */
	function setMiningGulpRange(uint256 _miningMinGulpAmount, uint256 _miningMaxGulpAmount) public override onlyOwner nonReentrant
	{
		drm.setMiningGulpRange(_miningMinGulpAmount, _miningMaxGulpAmount);
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
	 *      balance. This method uses the GCDelegatedReserveManager to
	 *      adjust the reserve. See GCDelegatedReserveManager.sol.
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
	 *      the amount that will be left in the reserve, in terms of cToken
	 *      cost, and adjusts the collateralization accordingly. This
	 *      method uses the GCDelegatedReserveManager to adjust the reserve.
	 *      See GCDelegatedReserveManager.sol.
	 * @param _cost The amount of reserve being withdrawn and that needs to
	 *              be immediately liquid.
	 * @return _success A boolean indicating whether or not the operation succeeded.
	 *                  The operation may fail if it is not possible to recover
	 *                  the required liquidity (e.g. low liquidity in the markets).
	 */
	function _prepareWithdrawal(uint256 _cost) internal override returns (bool _success)
	{
		return drm.adjustReserve(GCFormulae._calcUnderlyingCostFromCost(_cost, GC.fetchExchangeRate(reserveToken)));
	}
}
