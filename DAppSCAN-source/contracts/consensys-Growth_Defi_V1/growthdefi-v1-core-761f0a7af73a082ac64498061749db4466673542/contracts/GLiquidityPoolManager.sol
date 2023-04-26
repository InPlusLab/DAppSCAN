// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { G } from "./G.sol";

/**
 * @dev This library implements data structure abstraction for the liquidity
 *      pool management code in order to circuvent the EVM contract size limit.
 *      It is therefore a public library shared by all gToken contracts and
 *      needs to be published alongside them. See GTokenBase.sol for further
 *      documentation.
 */
library GLiquidityPoolManager
{
	using GLiquidityPoolManager for GLiquidityPoolManager.Self;

	uint256 constant MAXIMUM_BURNING_RATE = 2e16; // 2%
	uint256 constant DEFAULT_BURNING_RATE = 5e15; // 0.5%
	uint256 constant BURNING_INTERVAL = 7 days;
	uint256 constant MIGRATION_INTERVAL = 7 days;

	enum State { Created, Allocated, Migrating, Migrated }

	struct Self {
		address stakesToken;
		address sharesToken;

		State state;
		address liquidityPool;

		uint256 burningRate;
		uint256 lastBurningTime;

		address migrationRecipient;
		uint256 migrationUnlockTime;
	}

	/**
	 * @dev Initializes the data structure. This method is exposed publicly.
	 * @param _stakesToken The ERC-20 token address to be used as stakes
	 *                     token (GRO).
	 * @param _sharesToken The ERC-20 token address to be used as shares
	 *                     token (gToken).
	 */
	function init(Self storage _self, address _stakesToken, address _sharesToken) public
	{
		_self.stakesToken = _stakesToken;
		_self.sharesToken = _sharesToken;

		_self.state = State.Created;
		_self.liquidityPool = address(0);

		_self.burningRate = DEFAULT_BURNING_RATE;
		_self.lastBurningTime = 0;

		_self.migrationRecipient = address(0);
		_self.migrationUnlockTime = uint256(-1);
	}

	/**
	 * @dev Verifies whether or not a liquidity pool is migrating or
	 *      has migrated. This method is exposed publicly.
	 * @return _hasMigrated A boolean indicating whether or not the pool
	 *                      migration has started.
	 */
	function hasMigrated(Self storage _self) public view returns (bool _hasMigrated)
	{
		return _self.state == State.Migrating || _self.state == State.Migrated;
	}

	/**
	 * @dev Moves the current balances (if any) of stakes and shares tokens
	 *      to the liquidity pool. This method is exposed publicly.
	 */
	function gulpPoolAssets(Self storage _self) public
	{
		if (!_self._hasPool()) return;
		G.joinPool(_self.liquidityPool, _self.stakesToken, G.getBalance(_self.stakesToken));
		G.joinPool(_self.liquidityPool, _self.sharesToken, G.getBalance(_self.sharesToken));
	}

	/**
	 * @dev Sets the liquidity pool burning rate. This method is exposed
	 *      publicly.
	 * @param _burningRate The percent value of the liquidity pool to be
	 *                     burned at each 7-day period.
	 */
	function setBurningRate(Self storage _self, uint256 _burningRate) public
	{
		require(_burningRate <= MAXIMUM_BURNING_RATE, "invalid rate");
		_self.burningRate = _burningRate;
	}

	/**
	 * @dev Burns a portion of the liquidity pool according to the defined
	 *      burning rate. It must happen at most once every 7-days. This
	 *      method does not actually burn the funds, but it will redeem
	 *      the amounts from the pool to the caller contract, which is then
	 *      assumed to perform the burn. This method is exposed publicly.
	 * @return _stakesAmount The amount of stakes (GRO) redeemed from the pool.
	 * @return _sharesAmount The amount of shares (gToken) redeemed from the pool.
	 */
	function burnPoolPortion(Self storage _self) public returns (uint256 _stakesAmount, uint256 _sharesAmount)
	{
		require(_self._hasPool(), "pool not available");
		require(now >= _self.lastBurningTime + BURNING_INTERVAL, "must wait lock interval");
		_self.lastBurningTime = now;
		return G.exitPool(_self.liquidityPool, _self.burningRate);
	}

	/**
	 * @dev Creates a fresh new liquidity pool and deposits the initial
	 *      amounts of the stakes token and the shares token. The pool
	 *      if configure 50%/50% with a 10% swap fee. This method is exposed
	 *      publicly.
	 * @param _stakesAmount The amount of stakes token initially deposited
	 *                      into the pool.
	 * @param _sharesAmount The amount of shares token initially deposited
	 *                      into the pool.
	 */
	function allocatePool(Self storage _self, uint256 _stakesAmount, uint256 _sharesAmount) public
	{
		require(_self.state == State.Created, "pool cannot be allocated");
		_self.state = State.Allocated;
		_self.liquidityPool = G.createPool(_self.stakesToken, _stakesAmount, _self.sharesToken, _sharesAmount);
	}

	/**
	 * @dev Initiates the liquidity pool migration by setting a funds
	 *      recipent and starting the clock towards the 7-day grace period.
	 *      This method is exposed publicly.
	 * @param _migrationRecipient The recipient address to where funds will
	 *                            be transfered.
	 */
	function initiatePoolMigration(Self storage _self, address _migrationRecipient) public
	{
		require(_self.state == State.Allocated || _self.state == State.Migrated, "migration unavailable");
		_self.state = State.Migrating;
		_self.migrationRecipient = _migrationRecipient;
		_self.migrationUnlockTime = now + MIGRATION_INTERVAL;
	}

	/**
	 * @dev Cancels the liquidity pool migration by reseting the procedure
	 *      to its original state. This method is exposed publicly.
	 * @return _migrationRecipient The address of the former recipient.
	 */
	function cancelPoolMigration(Self storage _self) public returns (address _migrationRecipient)
	{
		require(_self.state == State.Migrating, "migration not initiated");
		_migrationRecipient = _self.migrationRecipient;
		_self.state = State.Allocated;
		_self.migrationRecipient = address(0);
		_self.migrationUnlockTime = uint256(-1);
		return _migrationRecipient;
	}

	/**
	 * @dev Completes the liquidity pool migration by redeeming all funds
	 *      from the pool. This method does not actually transfer the
	 *      redemeed funds to the recipient, it assumes the caller contract
	 *      will perform that. This method is exposed publicly.
	 * @return _migrationRecipient The address of the recipient.
	 * @return _stakesAmount The amount of stakes (GRO) redeemed from the pool.
	 * @return _sharesAmount The amount of shares (gToken) redeemed from the pool.
	 */
	function completePoolMigration(Self storage _self) public returns (address _migrationRecipient, uint256 _stakesAmount, uint256 _sharesAmount)
	{
		require(_self.state == State.Migrating, "migration not initiated");
		require(now >= _self.migrationUnlockTime, "must wait lock interval");
		_migrationRecipient = _self.migrationRecipient;
		_self.state = State.Migrated;
		_self.migrationRecipient = address(0);
		_self.migrationUnlockTime = uint256(-1);
		(_stakesAmount, _sharesAmount) = G.exitPool(_self.liquidityPool, 1e18);
		return (_migrationRecipient, _stakesAmount, _sharesAmount);
	}

	/**
	 * @dev Verifies whether or not a liquidity pool has been allocated.
	 * @return _poolAvailable A boolean indicating whether or not the pool
	 *                        is available.
	 */
	function _hasPool(Self storage _self) internal view returns (bool _poolAvailable)
	{
		return _self.state != State.Created;
	}
}
