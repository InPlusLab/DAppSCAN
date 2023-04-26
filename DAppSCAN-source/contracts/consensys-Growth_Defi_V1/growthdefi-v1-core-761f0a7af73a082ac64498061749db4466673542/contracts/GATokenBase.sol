// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { GFormulae } from "./GFormulae.sol";
import { GTokenBase } from "./GTokenBase.sol";
import { GCToken } from "./GCToken.sol";
import { GCFormulae } from "./GCFormulae.sol";
import { GMining } from "./GMining.sol";
import { G } from "./G.sol";
import { GA } from "./GA.sol";

/**
 * @notice This abstract contract provides the basis implementation for all
 *         gaTokens, i.e. gTokens that use Aave aTokens as reserve, and
 *         implements the common functionality shared amongst them.
 *         In a nutshell, it extends the functinality of the GTokenBase contract
 *         to support operating directly using the aToken underlying asset.
 *         Therefore this contract provides functions that encapsulate minting
 *         and redeeming of aTokens internally, allowing users to interact with
 *         the contract providing funds directly in their underlying asset.
 */
abstract contract GATokenBase is GTokenBase, GCToken, GMining
{
	address public immutable override miningToken; // unused
	address public immutable override growthToken;
	address public immutable override underlyingToken;

	/**
	 * @dev Constructor for the gaToken contract.
	 * @param _name The ERC-20 token name.
	 * @param _symbol The ERC-20 token symbol.
	 * @param _decimals The ERC-20 token decimals.
	 * @param _stakesToken The ERC-20 token address to be used as stakes
	 *                     token (GRO).
	 * @param _reserveToken The ERC-20 token address to be used as reserve
	 *                      token (e.g. aLINK for gacLINK).
	 * @param _growthToken The ERC-20 token address of the associated gToken.
	 */
	constructor (string memory _name, string memory _symbol, uint8 _decimals, address _stakesToken, address _reserveToken, address _growthToken)
		GTokenBase(_name, _symbol, _decimals, _stakesToken, _reserveToken) public
	{
		miningToken = address(0);
		growthToken = _growthToken;
		address _underlyingToken = GA.getUnderlyingToken(_reserveToken);
		underlyingToken = _underlyingToken;
	}

	/**
	 * @notice Allows for the beforehand calculation of the aToken amount
	 *         given the amount of the underlying token and an exchange rate.
	 * @param _underlyingCost The cost in terms of the aToken underlying asset.
	 * @param _exchangeRate The given exchange rate as provided by exchangeRate().
	 * @return _cost The equivalent cost in terms of aToken
	 */
	function calcCostFromUnderlyingCost(uint256 _underlyingCost, uint256 _exchangeRate) public pure override returns (uint256 _cost)
	{
		return GCFormulae._calcCostFromUnderlyingCost(_underlyingCost, _exchangeRate);
	}

	/**
	 * @notice Allows for the beforehand calculation of the underlying token
	 *         amount given the aToken amount and an exchange rate.
	 * @param _cost The cost in terms of the aToken.
	 * @param _exchangeRate The given exchange rate as provided by exchangeRate().
	 * @return _underlyingCost The equivalent cost in terms of the aToken underlying asset.
	 */
	function calcUnderlyingCostFromCost(uint256 _cost, uint256 _exchangeRate) public pure override returns (uint256 _underlyingCost)
	{
		return GCFormulae._calcUnderlyingCostFromCost(_cost, _exchangeRate);
	}

	/**
	 * @notice Allows for the beforehand calculation of shares to be
	 *         received/minted upon depositing the underlying asset to the
	 *         contract.
	 * @param _underlyingCost The amount of the underlying asset being deposited.
	 * @param _totalReserve The reserve balance as obtained by totalReserve().
	 * @param _totalSupply The shares supply as obtained by totalSupply().
	 * @param _depositFee The current deposit fee as obtained by depositFee().
	 * @param _exchangeRate The exchange rate as obtained by exchangeRate().
	 * @return _netShares The net amount of shares being received.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcDepositSharesFromUnderlyingCost(uint256 _underlyingCost, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee, uint256 _exchangeRate) public pure override returns (uint256 _netShares, uint256 _feeShares)
	{
		return GCFormulae._calcDepositSharesFromUnderlyingCost(_underlyingCost, _totalReserve, _totalSupply, _depositFee, _exchangeRate);
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of the
	 *         underlying asset to be deposited in order to receive the desired
	 *         amount of shares.
	 * @param _netShares The amount of this gcToken shares to receive.
	 * @param _totalReserve The reserve balance as obtained by totalReserve().
	 * @param _totalSupply The shares supply as obtained by totalSupply().
	 * @param _depositFee The current deposit fee as obtained by depositFee().
	 * @param _exchangeRate The exchange rate as obtained by exchangeRate().
	 * @return _underlyingCost The cost, in the underlying asset, to be paid.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcDepositUnderlyingCostFromShares(uint256 _netShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee, uint256 _exchangeRate) public pure override returns (uint256 _underlyingCost, uint256 _feeShares)
	{
		return GCFormulae._calcDepositUnderlyingCostFromShares(_netShares, _totalReserve, _totalSupply, _depositFee, _exchangeRate);
	}

	/**
	 * @notice Allows for the beforehand calculation of shares to be
	 *         given/burned upon withdrawing the underlying asset from the
	 *         contract.
	 * @param _underlyingCost The amount of the underlying asset being withdrawn.
	 * @param _totalReserve The reserve balance as obtained by totalReserve()
	 * @param _totalSupply The shares supply as obtained by totalSupply()
	 * @param _withdrawalFee The current withdrawl fee as obtained by withdrawalFee()
	 * @param _exchangeRate The exchange rate as obtained by exchangeRate().
	 * @return _grossShares The total amount of shares being deducted,
	 *                      including fees.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcWithdrawalSharesFromUnderlyingCost(uint256 _underlyingCost, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee, uint256 _exchangeRate) public pure override returns (uint256 _grossShares, uint256 _feeShares)
	{
		return GCFormulae._calcWithdrawalSharesFromUnderlyingCost(_underlyingCost, _totalReserve, _totalSupply, _withdrawalFee, _exchangeRate);
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of the
	 *         underlying asset to be withdrawn given the desired amount of
	 *         shares.
	 * @param _grossShares The amount of this gcToken shares to provide.
	 * @param _totalReserve The reserve balance as obtained by totalReserve().
	 * @param _totalSupply The shares supply as obtained by totalSupply().
	 * @param _withdrawalFee The current withdrawal fee as obtained by withdrawalFee().
	 * @param _exchangeRate The exchange rate as obtained by exchangeRate().
	 * @return _underlyingCost The cost, in the underlying asset, to be received.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcWithdrawalUnderlyingCostFromShares(uint256 _grossShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee, uint256 _exchangeRate) public pure override returns (uint256 _underlyingCost, uint256 _feeShares)
	{
		return GCFormulae._calcWithdrawalUnderlyingCostFromShares(_grossShares, _totalReserve, _totalSupply, _withdrawalFee, _exchangeRate);
	}

	/**
	 * @notice Provides the Aave exchange rate since their last update.
	 * @return _exchangeRate The exchange rate between aToken and its
	 *                       underlying asset
	 */
	function exchangeRate() public view override returns (uint256 _exchangeRate)
	{
		return GA.getExchangeRate(reserveToken);
	}

	/**
	 * @notice Provides the total amount kept in the reserve in terms of the
	 *         underlying asset.
	 * @return _totalReserveUnderlying The underlying asset balance on reserve.
	 */
	function totalReserveUnderlying() public view virtual override returns (uint256 _totalReserveUnderlying)
	{
		return GCFormulae._calcUnderlyingCostFromCost(totalReserve(), exchangeRate());
	}

	/**
	 * @notice Provides the total amount of the underlying asset (or equivalent)
	 *         this contract is currently lending on Aave.
	 * @return _lendingReserveUnderlying The underlying asset lending
	 *                                   balance on Aave.
	 */
	function lendingReserveUnderlying() public view virtual override returns (uint256 _lendingReserveUnderlying)
	{
		return GA.getLendAmount(reserveToken);
	}

	/**
	 * @notice Provides the total amount of the underlying asset (or equivalent)
	 *         this contract is currently borrowing on Aave.
	 * @return _borrowingReserveUnderlying The underlying asset borrowing
	 *                                     balance on Aave.
	 */
	function borrowingReserveUnderlying() public view virtual override returns (uint256 _borrowingReserveUnderlying)
	{
		return GA.getBorrowAmount(reserveToken);
	}

	/**
	 * @notice Performs the minting of gaToken shares upon the deposit of the
	 *         cToken underlying asset. The funds will be pulled in by this
	 *         contract, therefore they must be previously approved. This
	 *         function builds upon the GTokenBase deposit function. See
	 *         GTokenBase.sol for further documentation.
	 * @param _underlyingCost The amount of the underlying asset being
	 *                        deposited in the operation.
	 */
	function depositUnderlying(uint256 _underlyingCost) public override nonReentrant
	{
		address _from = msg.sender;
		require(_underlyingCost > 0, "underlying cost must be greater than 0");
		uint256 _cost = GCFormulae._calcCostFromUnderlyingCost(_underlyingCost, exchangeRate());
		(uint256 _netShares, uint256 _feeShares) = GFormulae._calcDepositSharesFromCost(_cost, totalReserve(), totalSupply(), depositFee());
		require(_netShares > 0, "shares must be greater than 0");
		G.pullFunds(underlyingToken, _from, _underlyingCost);
		GA.safeLend(reserveToken, _underlyingCost);
		require(_prepareDeposit(_cost), "not available at the moment");
		_mint(_from, _netShares);
		_mint(address(this), _feeShares.div(2));
	}

	/**
	 * @notice Performs the burning of gaToken shares upon the withdrawal of
	 *         the underlying asset. This function builds upon the
	 *         GTokenBase withdrawal function. See GTokenBase.sol for
	 *         further documentation.
	 * @param _grossShares The gross amount of this gaToken shares being
	 *                     redeemed in the operation.
	 */
	function withdrawUnderlying(uint256 _grossShares) public override nonReentrant
	{
		address _from = msg.sender;
		require(_grossShares > 0, "shares must be greater than 0");
		(uint256 _cost, uint256 _feeShares) = GFormulae._calcWithdrawalCostFromShares(_grossShares, totalReserve(), totalSupply(), withdrawalFee());
		uint256 _underlyingCost = GCFormulae._calcUnderlyingCostFromCost(_cost, exchangeRate());
		require(_underlyingCost > 0, "underlying cost must be greater than 0");
		require(_prepareWithdrawal(_cost), "not available at the moment");
		_underlyingCost = G.min(_underlyingCost, GA.getLendAmount(reserveToken));
		GA.safeRedeem(reserveToken, _underlyingCost);
		G.pushFunds(underlyingToken, _from, _underlyingCost);
		_burn(_from, _grossShares);
		_mint(address(this), _feeShares.div(2));
	}
}
