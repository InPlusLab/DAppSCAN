// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { GTokenBase } from "./GTokenBase.sol";
import { GPortfolioReserveManager } from "./GPortfolioReserveManager.sol";

/**
 * @notice This contract implements the functionality for the gToken Type 0.
 *         The gToken Type 0 provides a simple portfolio management strategy
 *         that splits the reserve asset percentually among multiple other
 *         gTokens. Also, it allows for part of the reserve to be kept liquid,
 *         in the reserve token itself, to save on gas fees. The contract owner
 *         can add and remove gTokens that compose the portfolio, as much as
 *         reconfigure their percentual shares. There is also a configurable
 *         rebalance margins that serves as threshold for when the contract will
 *         or not attempt to rebalance the reserve according to the set
 *         percentual ratios. The algorithm that maintains the proper
 *         distribution of the reserve token does so incrementally based on the
 *         following principles: 1) At each deposit/withdrawal, at most one
 *         underlying deposit/withdrawal is performed; 2) When the
 *         deposit/withdrawal can be served from the liquid pool, and within the
 *         bounds of the rebalance margin, no underlying deposit/withdrawal is
 *         performed; 3) When performing a rebalance the gToken with the
 *         most discrepant reserve share is chosen for rebalancing; 4) When
 *         performing an withdrawal, if it cannot be served entirely from
 *         the liquid pool, the we choose the gToken that can provide the
 *         required additional liquidity with the least percentual impact to
 *         its reserve share. As with all gTokens, gTokens Type 0 have an
 *         associated locked liquidity pool and follow the same fee structure.
 *         See GTokenBase and GPortfolioReserveManager for further documentation.
 */
contract GTokenType0 is GTokenBase
{
	using GPortfolioReserveManager for GPortfolioReserveManager.Self;

	GPortfolioReserveManager.Self prm;

	/**
	 * @dev Constructor for the gToken Type 0 contract.
	 * @param _name The ERC-20 token name.
	 * @param _symbol The ERC-20 token symbol.
	 * @param _decimals The ERC-20 token decimals.
	 * @param _stakesToken The ERC-20 token address to be used as stakes
	 *                     token (GRO).
	 * @param _reserveToken The ERC-20 token address to be used as reserve
	 *                      token (e.g. DAI for gDAI).
	 */
	constructor (string memory _name, string memory _symbol, uint8 _decimals, address _stakesToken, address _reserveToken)
		GTokenBase(_name, _symbol, _decimals, _stakesToken, _reserveToken) public
	{
		prm.init(_reserveToken);
	}

	/**
	 * @notice Overrides the default total reserve definition in order to
	 *         account, not only for the reserve asset being kept liquid by
	 *         this contract, but also sum up the reserve portions delegated
	 *         to all gTokens that make up the portfolio.
	 * @return _totalReserve The amount of the reserve token corresponding
	 *                       to this contract's worth.
	 */
	function totalReserve() public view virtual override returns (uint256 _totalReserve)
	{
		return prm.totalReserve();
	}

	/**
	 * @notice Provides the number of gTokens that were added to this
	 *         contract by the owner.
	 * @return _count The number of gTokens that make up the portfolio.
	 */
	function tokenCount() public view returns (uint256 _count)
	{
		return prm.tokenCount();
	}

	/**
	 * @notice Provides a gToken that was added to this contract by the owner
	 *         at a given index. Note that the index to token association
	 *         is preserved in between token removals, however removals may
	 *         may shuffle it around.
	 * @param _index The desired index, must be less than the token count.
	 * @return _token The gToken currently present at the given index.
	 */
	function tokenAt(uint256 _index) public view returns (address _token)
	{
		return prm.tokenAt(_index);
	}

	/**
	 * @notice Provides the percentual share of a gToken in the composition
	 *         of the portfolio. Note that the value returned is the desired
	 *         percentual share and not the actual reserve share.
	 * @param _token The given token address.
	 * @return _percent The token percentual share of the portfolio, as
	 *                  configured by the owner.
	 */
	function tokenPercent(address _token) public view returns (uint256 _percent)
	{
		return prm.tokenPercent(_token);
	}

	/**
	 * @notice Provides the percentual margins tolerable before triggering a
	 *         rebalance action (i.e. an underlying deposit or withdrawal).
	 * @return _liquidRebalanceMargin The liquid percentual rebalance margin,
	 *                                as configured by the owner.
	 * @return _portfolioRebalanceMargin The portfolio percentual rebalance
	 *                                   margin, as configured by the owner.
	 */
	function getRebalanceMargins() public view returns (uint256 _liquidRebalanceMargin, uint256 _portfolioRebalanceMargin)
	{
		return (prm.liquidRebalanceMargin, prm.portfolioRebalanceMargin);
	}

	/**
	 * @notice Inserts a new gToken into the portfolio. The new gToken must
	 *         have the reserve token as its underlying token. The initial
	 *         portfolio share of the new token will be 0%.
	 * @param _token The contract address of the new gToken to be incorporated
	 *               into the portfolio.
	 */
	function insertToken(address _token) public onlyOwner nonReentrant
	{
		prm.insertToken(_token);
	}

	/**
	 * @notice Removes a gToken from the portfolio. The portfolio share of
	 *         the token must be 0% before it can be removed. The underlying
	 *         reserve is redeemed upon removal.
	 * @param _token The contract address of the gToken to be removed from
	 *               the portfolio.
	 */
	function removeToken(address _token) public onlyOwner nonReentrant
	{
		prm.removeToken(_token);
	}

	/**
	 * @notice Shifts a percentual share of the portfolio allocation from
	 *         one gToken to another gToken. The reserve token can also be
	 *         used as source or target of the operation. This does not
	 *         actually shifts funds, only reconfigures the allocation.
	 * @param _sourceToken The token address to provide the share.
	 * @param _targetToken The token address to receive the share.
	 * @param _percent The percentual share to shift.
	 */
	function transferTokenPercent(address _sourceToken, address _targetToken, uint256 _percent) public onlyOwner nonReentrant
	{
		prm.transferTokenPercent(_sourceToken, _targetToken, _percent);
	}

	/**
	 * @notice Sets the percentual margins tolerable before triggering a
	 *         rebalance action (i.e. an underlying deposit or withdrawal).
	 * @param _liquidRebalanceMargin The liquid percentual rebalance margin,
	 *                               to be configured by the owner.
	 * @param _portfolioRebalanceMargin The portfolio percentual rebalance
	 *                                  margin, to be configured by the owner.
	 */
	function setRebalanceMargins(uint256 _liquidRebalanceMargin, uint256 _portfolioRebalanceMargin) public onlyOwner nonReentrant
	{
		prm.setRebalanceMargins(_liquidRebalanceMargin, _portfolioRebalanceMargin);
	}

	/**
	 * @dev This method is overriden from GTokenBase and sets up the reserve
	 *      after a deposit comes along. This method uses the GPortfolioReserveManager
	 *      to adjust the reserve implementing the rebalance policy.
	 *      See GPortfolioReserveManager.sol.
	 * @param _cost The amount of reserve being deposited (ignored).
	 * @return _success A boolean indicating whether or not the operation
	 *                  succeeded. This operation should not fail unless
	 *                  any of the underlying components (Compound, Aave,
	 *                  Dydx) also fails.
	 */
	function _prepareDeposit(uint256 _cost) internal override returns (bool _success)
	{
		_cost; // silences warnings
		return prm.adjustReserve(0);
	}

	/**
	 * @dev This method is overriden from GTokenBase and sets up the reserve
	 *      before a withdrawal comes along. This method uses the GPortfolioReserveManager
	 *      to adjust the reserve implementing the rebalance policy.
	 *      See GPortfolioReserveManager.sol.
	 * @param _cost The amount of reserve being withdrawn and that needs to
	 *              be immediately liquid.
	 * @return _success A boolean indicating whether or not the operation succeeded.
	 *                  The operation may fail if it is not possible to recover
	 *                  the required liquidity (e.g. low liquidity in the markets).
	 */
	function _prepareWithdrawal(uint256 _cost) internal override returns (bool _success)
	{
		return prm.adjustReserve(_cost);
	}
}
