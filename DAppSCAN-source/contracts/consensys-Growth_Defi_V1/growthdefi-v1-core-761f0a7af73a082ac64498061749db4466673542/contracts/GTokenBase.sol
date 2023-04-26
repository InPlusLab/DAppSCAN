// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { GToken } from "./GToken.sol";
import { GPooler } from "./GPooler.sol";
import { GFormulae } from "./GFormulae.sol";
import { GLiquidityPoolManager } from "./GLiquidityPoolManager.sol";
import { G } from "./G.sol";

/**
 * @notice This abstract contract provides the basis implementation for all
 *         gTokens. It extends the ERC20 functionality by implementing all
 *         the methods of the GToken interface. The gToken basic functionality
 *         comprises of a reserve, provided in the reserve token, and a supply
 *         of shares. Every time someone deposits into the contract some amount
 *         of reserve tokens it will receive a given amount of this gToken
 *         shares. Conversely, upon withdrawal, someone redeems their previously
 *         deposited assets by providing the associated amount of gToken shares.
 *         The nominal price of a gToken is given by the ratio between the
 *         reserve balance and the total supply of shares. Upon deposit and
 *         withdrawal of funds a 1% fee is applied and collected from shares.
 *         Half of it is immediately burned, which is equivalent to
 *         redistributing it to all gToken holders, and the other half is
 *         provided to a liquidity pool configured as a 50% GRO/50% gToken with
 *         a 10% swap fee. Every week a percentage of the liquidity pool is
 *         burned to account for the accumulated swap fees for that period.
 *         Finally, the gToken contract provides functionality to migrate the
 *         total amount of funds locked in the liquidity pool to an external
 *         address, this mechanism is provided to facilitate the upgrade of
 *         this gToken contract by future implementations. After migration has
 *         started the fee for deposits becomes 2% and the fee for withdrawals
 *         becomes 0%, in order to incentivise others to follow the migration.
 */
abstract contract GTokenBase is ERC20, Ownable, ReentrancyGuard, GToken, GPooler
{
	using GLiquidityPoolManager for GLiquidityPoolManager.Self;

	uint256 constant DEPOSIT_FEE = 1e16; // 1%
	uint256 constant WITHDRAWAL_FEE = 1e16; // 1%
	uint256 constant DEPOSIT_FEE_AFTER_MIGRATION = 2e16; // 2%
	uint256 constant WITHDRAWAL_FEE_AFTER_MIGRATION = 0e16; // 0%

	address public immutable override stakesToken;
	address public immutable override reserveToken;

	GLiquidityPoolManager.Self lpm;

	/**
	 * @dev Constructor for the gToken contract.
	 * @param _name The ERC-20 token name.
	 * @param _symbol The ERC-20 token symbol.
	 * @param _decimals The ERC-20 token decimals.
	 * @param _stakesToken The ERC-20 token address to be used as stakes
	 *                     token (GRO).
	 * @param _reserveToken The ERC-20 token address to be used as reserve
	 *                      token (e.g. cDAI for gcDAI).
	 */
	constructor (string memory _name, string memory _symbol, uint8 _decimals, address _stakesToken, address _reserveToken)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		stakesToken = _stakesToken;
		reserveToken = _reserveToken;
		lpm.init(_stakesToken, address(this));
	}

	/**
	 * @notice Allows for the beforehand calculation of shares to be
	 *         received/minted upon depositing to the contract.
	 * @param _cost The amount of reserve token being deposited.
	 * @param _totalReserve The reserve balance as obtained by totalReserve().
	 * @param _totalSupply The shares supply as obtained by totalSupply().
	 * @param _depositFee The current deposit fee as obtained by depositFee().
	 * @return _netShares The net amount of shares being received.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcDepositSharesFromCost(uint256 _cost, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee) public pure override returns (uint256 _netShares, uint256 _feeShares)
	{
		return GFormulae._calcDepositSharesFromCost(_cost, _totalReserve, _totalSupply, _depositFee);
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reserve token to be deposited in order to receive the desired
	 *         amount of shares.
	 * @param _netShares The amount of this gToken shares to receive.
	 * @param _totalReserve The reserve balance as obtained by totalReserve().
	 * @param _totalSupply The shares supply as obtained by totalSupply().
	 * @param _depositFee The current deposit fee as obtained by depositFee().
	 * @return _cost The cost, in the reserve token, to be paid.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcDepositCostFromShares(uint256 _netShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee) public pure override returns (uint256 _cost, uint256 _feeShares)
	{
		return GFormulae._calcDepositCostFromShares(_netShares, _totalReserve, _totalSupply, _depositFee);
	}

	/**
	 * @notice Allows for the beforehand calculation of shares to be
	 *         given/burned upon withdrawing from the contract.
	 * @param _cost The amount of reserve token being withdrawn.
	 * @param _totalReserve The reserve balance as obtained by totalReserve()
	 * @param _totalSupply The shares supply as obtained by totalSupply()
	 * @param _withdrawalFee The current withdrawal fee as obtained by withdrawalFee()
	 * @return _grossShares The total amount of shares being deducted,
	 *                      including fees.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcWithdrawalSharesFromCost(uint256 _cost, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee) public pure override returns (uint256 _grossShares, uint256 _feeShares)
	{
		return GFormulae._calcWithdrawalSharesFromCost(_cost, _totalReserve, _totalSupply, _withdrawalFee);
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reserve token to be withdrawn given the desired amount of
	 *         shares.
	 * @param _grossShares The amount of this gToken shares to provide.
	 * @param _totalReserve The reserve balance as obtained by totalReserve().
	 * @param _totalSupply The shares supply as obtained by totalSupply().
	 * @param _withdrawalFee The current withdrawal fee as obtained by withdrawalFee().
	 * @return _cost The cost, in the reserve token, to be received.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcWithdrawalCostFromShares(uint256 _grossShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee) public pure override returns (uint256 _cost, uint256 _feeShares)
	{
		return GFormulae._calcWithdrawalCostFromShares(_grossShares, _totalReserve, _totalSupply, _withdrawalFee);
	}

	/**
	 * @notice Provides the amount of reserve tokens currently being help by
	 *         this contract.
	 * @return _totalReserve The amount of the reserve token corresponding
	 *                       to this contract's balance.
	 */
	function totalReserve() public view virtual override returns (uint256 _totalReserve)
	{
		return G.getBalance(reserveToken);
	}

	/**
	 * @notice Provides the current minting/deposit fee. This fee is
	 *         applied to the amount of this gToken shares being created
	 *         upon deposit. The fee defaults to 1% and is set to 2%
	 *         after the liquidity pool has been migrated.
	 * @return _depositFee A percent value that accounts for the percentage
	 *                     of shares being minted at each deposit that be
	 *                     collected as fee.
	 */
	function depositFee() public view override returns (uint256 _depositFee) {
		return lpm.hasMigrated() ? DEPOSIT_FEE_AFTER_MIGRATION : DEPOSIT_FEE;
	}

	/**
	 * @notice Provides the current burning/withdrawal fee. This fee is
	 *         applied to the amount of this gToken shares being redeemed
	 *         upon withdrawal. The fee defaults to 1% and is set to 0%
	 *         after the liquidity pool is migrated.
	 * @return _withdrawalFee A percent value that accounts for the
	 *                        percentage of shares being burned at each
	 *                        withdrawal that be collected as fee.
	 */
	function withdrawalFee() public view override returns (uint256 _withdrawalFee) {
		return lpm.hasMigrated() ? WITHDRAWAL_FEE_AFTER_MIGRATION : WITHDRAWAL_FEE;
	}

	/**
	 * @notice Provides the address of the liquidity pool contract.
	 * @return _liquidityPool An address identifying the liquidity pool.
	 */
	function liquidityPool() public view override returns (address _liquidityPool)
	{
		return lpm.liquidityPool;
	}

	/**
	 * @notice Provides the percentage of the liquidity pool to be burned.
	 *         This amount should account approximately for the swap fees
	 *         collected by the liquidity pool during a 7-day period.
	 * @return _burningRate A percent value that corresponds to the current
	 *                      amount of the liquidity pool to be burned at
	 *                      each 7-day cycle.
	 */
	function liquidityPoolBurningRate() public view override returns (uint256 _burningRate)
	{
		return lpm.burningRate;
	}

	/**
	 * @notice Marks when the last liquidity pool burn took place. There is
	 *         a minimum 7-day grace period between consecutive burnings of
	 *         the liquidity pool.
	 * @return _lastBurningTime A timestamp for when the liquidity pool
	 *                          burning took place for the last time.
	 */
	function liquidityPoolLastBurningTime() public view override returns (uint256 _lastBurningTime)
	{
		return lpm.lastBurningTime;
	}

	/**
	 * @notice Provides the address receiving the liquidity pool migration.
	 * @return _migrationRecipient An address to which funds will be sent
	 *                             upon liquidity pool migration completion.
	 */
	function liquidityPoolMigrationRecipient() public view override returns (address _migrationRecipient)
	{
		return lpm.migrationRecipient;
	}

	/**
	 * @notice Provides the timestamp for when the liquidity pool migration
	 *         can be completed.
	 * @return _migrationUnlockTime A timestamp that defines the end of the
	 *                              7-day grace period for liquidity pool
	 *                              migration.
	 */
	function liquidityPoolMigrationUnlockTime() public view override returns (uint256 _migrationUnlockTime)
	{
		return lpm.migrationUnlockTime;
	}

	/**
	 * @notice Performs the minting of gToken shares upon the deposit of the
	 *         reserve token. The actual number of shares being minted can
	 *         be calculated using the calcDepositSharesFromCost function.
	 *         In every deposit, 1% of the shares is retained in terms of
	 *         deposit fee. Half of it is immediately burned and the other
	 *         half is provided to the locked liquidity pool. The funds
	 *         will be pulled in by this contract, therefore they must be
	 *         previously approved.
	 * @param _cost The amount of reserve token being deposited in the
	 *              operation.
	 */
	function deposit(uint256 _cost) public override nonReentrant
	{
		address _from = msg.sender;
		require(_cost > 0, "cost must be greater than 0");
		(uint256 _netShares, uint256 _feeShares) = GFormulae._calcDepositSharesFromCost(_cost, totalReserve(), totalSupply(), depositFee());
		require(_netShares > 0, "shares must be greater than 0");
		G.pullFunds(reserveToken, _from, _cost);
		require(_prepareDeposit(_cost), "not available at the moment");
		_mint(_from, _netShares);
		_mint(address(this), _feeShares.div(2));
	}

	/**
	 * @notice Performs the burning of gToken shares upon the withdrawal of
	 *         the reserve token. The actual amount of the reserve token to
	 *         be received can be calculated using the
	 *         calcWithdrawalCostFromShares function. In every withdrawal,
	 *         1% of the shares is retained in terms of withdrawal fee.
	 *         Half of it is immediately burned and the other half is
	 *         provided to the locked liquidity pool.
	 * @param _grossShares The gross amount of this gToken shares being
	 *                     redeemed in the operation.
	 */
	function withdraw(uint256 _grossShares) public override nonReentrant
	{
		address _from = msg.sender;
		require(_grossShares > 0, "shares must be greater than 0");
		(uint256 _cost, uint256 _feeShares) = GFormulae._calcWithdrawalCostFromShares(_grossShares, totalReserve(), totalSupply(), withdrawalFee());
		require(_cost > 0, "cost must be greater than 0");
		require(_prepareWithdrawal(_cost), "not available at the moment");
		_cost = G.min(_cost, G.getBalance(reserveToken));
		G.pushFunds(reserveToken, _from, _cost);
		_burn(_from, _grossShares);
		_mint(address(this), _feeShares.div(2));
	}

	/**
	 * @notice Allocates a liquidity pool with the given amount of funds and
	 *         locks it to this contract. This function should be called
	 *         shortly after the contract is created to associated a newly
	 *         created liquidity pool to it, which will collect fees
	 *         associated with the minting and burning of this gToken shares.
	 *         The liquidity pool will consist of a 50%/50% balance of the
	 *         stakes token (GRO) and this gToken shares with a swap fee of
	 *         10%. The rate between the amount of the two assets deposited
	 *         via this function defines the initial price. The minimum
	 *         amount to be provided for each is 1,000,000 wei. The funds
	 *         will be pulled in by this contract, therefore they must be
	 *         previously approved. This is a priviledged function
	 *         restricted to the contract owner.
	 * @param _stakesAmount The initial amount of stakes token.
	 * @param _sharesAmount The initial amount of this gToken shares.
	 */
	function allocateLiquidityPool(uint256 _stakesAmount, uint256 _sharesAmount) public override onlyOwner nonReentrant
	{
		address _from = msg.sender;
		G.pullFunds(stakesToken, _from, _stakesAmount);
		_transfer(_from, address(this), _sharesAmount);
		lpm.allocatePool(_stakesAmount, _sharesAmount);
	}

	/**
	 * @notice Changes the percentual amount of the funds to be burned from
	 *         the liquidity pool at each 7-day period. This is a
	 *         priviledged function restricted to the contract owner.
	 * @param _burningRate The percentage of the liquidity pool to be burned.
	 */
	function setLiquidityPoolBurningRate(uint256 _burningRate) public override onlyOwner nonReentrant
	{
		lpm.setBurningRate(_burningRate);
	}

	/**
	 * @notice Burns part of the liquidity pool funds decreasing the supply
	 *         of both the stakes token and this gToken shares.
	 *         The amount to be burned is set via the function
	 *         setLiquidityPoolBurningRate and defaults to 0.5%.
	 *         After this function is called there must be a 7-day wait
	 *         period before it can be called again.
	 *         The purpose of this function is to burn the aproximate amount
	 *         of fees collected from swaps that take place in the liquidity
	 *         pool during the previous 7-day period. This function will
	 *         emit a BurnLiquidityPoolPortion event upon success. This is
	 *         a priviledged function restricted to the contract owner.
	 */
	function burnLiquidityPoolPortion() public override onlyOwner nonReentrant
	{
		lpm.gulpPoolAssets();
		(uint256 _stakesAmount, uint256 _sharesAmount) = lpm.burnPoolPortion();
		_burnStakes(_stakesAmount);
		_burn(address(this), _sharesAmount);
		emit BurnLiquidityPoolPortion(_stakesAmount, _sharesAmount);
	}

	/**
	 * @notice Initiates the liquidity pool migration. It consists of
	 *         setting the migration recipient address and starting a
	 *         7-day grace period. After the 7-day grace period the
	 *         migration can be completed via the
	 *         completeLiquidityPoolMigration fuction. Anytime before
	 *         the migration is completed is can be cancelled via
	 *         cancelLiquidityPoolMigration. This function will emit a
	 *         InitiateLiquidityPoolMigration event upon success. This is
	 *         a priviledged function restricted to the contract owner.
	 * @param _migrationRecipient The receiver of the liquidity pool funds.
	 */
	function initiateLiquidityPoolMigration(address _migrationRecipient) public override onlyOwner nonReentrant
	{
		lpm.initiatePoolMigration(_migrationRecipient);
		emit InitiateLiquidityPoolMigration(_migrationRecipient);
	}

	/**
	 * @notice Cancels the liquidity pool migration if it has been already
	 *         initiated. This will reset the state of the liquidity pool
	 *         migration. This function will emit a
	 *         CancelLiquidityPoolMigration event upon success. This is
	 *         a priviledged function restricted to the contract owner.
	 */
	function cancelLiquidityPoolMigration() public override onlyOwner nonReentrant
	{
		address _migrationRecipient = lpm.cancelPoolMigration();
		emit CancelLiquidityPoolMigration(_migrationRecipient);
	}

	/**
	 * @notice Completes the liquidity pool migration at least 7-days after
	 *         it has been started. The migration consists of sendind the
	 *         the full balance held in the liquidity pool, both in the
	 *         stakes token and gToken shares, to the address set when
	 *         the migration was initiated. This function will emit a
	 *         CompleteLiquidityPoolMigration event upon success. This is
	 *         a priviledged function restricted to the contract owner.
	 */
	function completeLiquidityPoolMigration() public override onlyOwner nonReentrant
	{
		lpm.gulpPoolAssets();
		(address _migrationRecipient, uint256 _stakesAmount, uint256 _sharesAmount) = lpm.completePoolMigration();
		G.pushFunds(stakesToken, _migrationRecipient, _stakesAmount);
		_transfer(address(this), _migrationRecipient, _sharesAmount);
		emit CompleteLiquidityPoolMigration(_migrationRecipient, _stakesAmount, _sharesAmount);
	}

	/**
	 * @dev This abstract method must be implemented by subcontracts in
	 *      order to adjust the underlying reserve after a deposit takes
	 *      place. The actual implementation depends on the strategy and
	 *      algorithm used to handle the reserve.
	 * @param _cost The amount of the reserve token being deposited.
	 */
	function _prepareDeposit(uint256 _cost) internal virtual returns (bool _success);

	/**
	 * @dev This abstract method must be implemented by subcontracts in
	 *      order to adjust the underlying reserve before a withdrawal takes
	 *      place. The actual implementation depends on the strategy and
	 *      algorithm used to handle the reserve.
	 * @param _cost The amount of the reserve token being withdrawn.
	 */
	function _prepareWithdrawal(uint256 _cost) internal virtual returns (bool _success);

	/**
	 * @dev Burns the given amount of the stakes token. The default behavior
	 *      of the function for general ERC-20 is to send the funds to
	 *      address(0), but that can be overriden by a subcontract.
	 * @param _stakesAmount The amount of the stakes token being burned.
	 */
	function _burnStakes(uint256 _stakesAmount) internal virtual
	{
		G.pushFunds(stakesToken, address(0), _stakesAmount);
	}
}
