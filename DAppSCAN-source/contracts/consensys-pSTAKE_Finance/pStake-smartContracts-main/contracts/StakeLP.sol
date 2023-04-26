/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IUTokensV2.sol";
import "./interfaces/IHolderV2.sol";
import "./interfaces/ISTokensV2.sol";
import "./interfaces/IStakeLP.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/FullMath.sol";
import "./interfaces/IWhitelistedPTokenEmission.sol";
import "./interfaces/IWhitelistedRewardEmission.sol";

contract StakeLP is
	IStakeLP,
	PausableUpgradeable,
	AccessControlUpgradeable,
	ReentrancyGuardUpgradeable
{
	using SafeMathUpgradeable for uint256;
	using FullMath for uint256;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	// constant pertaining to access roles
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	// valueDivisor to store fractional values for various reward attributes like _rewardTokenEmission
	uint256 public _valueDivisor;
	// variable pertaining to contract upgrades versioning
	uint256 public _version;

	// -------------------------------------------------------------------------
	// -------------------------------------------------------------------------

	// VARIABLES PERTAINING TO CALCULATION OF LPTIMESHARE
	// balance of user, for an LP Token
	mapping(address => mapping(address => uint256)) public _lpBalance;
	// supply of LP tokens reserve, for an LP Token
	mapping(address => uint256) public _lpSupply;
	// last updated total LPTimeShare, for an LP Token
	mapping(address => uint256) public _lastLPTimeShare;
	// last recorded timestamp when user's LPTimeShare was updated, for a user, for an LP Token
	mapping(address => mapping(address => uint256))
		public _lastLiquidityTimestamp;

	// -------------------------------------------------------------------------
	// -------------------------------------------------------------------------

	// required to store the whitelisting holder logic data for PToken rewards, initiated from WhitelistedEmission contract
	address public _whitelistedPTokenEmissionContract;
	// required to store the whitelisting holder logic data for other rewards, initiated from WhitelistedEmission contract
	address public _whitelistedRewardEmissionContract;

	/**
	 * @dev Constructor for initializing the stakeLP contract.
	 * @param pauserAddress - address of the pauser admin.
	 * @param whitelistedPTokenEmissionContract - address of whitelistedPTokenEmission Contract.
	 * @param whitelistedRewardEmissionContract - address of whitelistedPTokenEmission Contract.
	 * @param valueDivisor - valueDivisor set to 10^9.
	 */
	function initialize(
		address pauserAddress,
		address whitelistedPTokenEmissionContract,
		address whitelistedRewardEmissionContract,
		uint256 valueDivisor
	) public virtual initializer {
		__AccessControl_init();
		__Pausable_init();
		_setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
		_setupRole(PAUSER_ROLE, pauserAddress);
		_whitelistedPTokenEmissionContract = whitelistedPTokenEmissionContract;
		_whitelistedRewardEmissionContract = whitelistedRewardEmissionContract;
		_valueDivisor = valueDivisor;
	}

	/*
	 * @dev calculate liquidity and reward tokens and disburse to user
	 * @param holderAddress: holder contract address
	 * @param accountAddress: user address
	 */
	function calculatePendingRewards(
		address holderAddress,
		address accountAddress
	)
		public
		view
		virtual
		override
		returns (
			uint256[] memory rewardAmounts,
			address[] memory rewardTokens,
			address[] memory sTokenAddresses,
			address lpTokenAddress,
			uint256 updatedSupplyLPTimeshare,
			uint256 newSupplyLPTimeShare
		)
	{
		uint256 _userLPTimeShare;
		uint256 _totalSupplyLPTimeShare;
		uint256[] memory holderRewards;

		// CALCULTE LP TOKEN RATIOS OF USER AND SUPPLY
		// CALCULATE PTOKENS REWARD EMISSION - CALCULATE (NOT TRIGGER) HOLDER REWARDS
		// CALCULATE PTOKENS REWARD SHARE OF USER - CALCULATE (NOT TRIGGER) REWARD CALC OF PTOKENS
		// CALCULATE OTHER REWARDS EMISSION - CALCULATE (NOT TRIGGER) OTHER PENDING REWARDS
		// CALCULATE OTHER REWARDS SHARE OF USER - CALCULATE (NOT TRIGGER) REWARD CALC OF OTHER TOKENS

		(
			holderRewards,
			sTokenAddresses,
			,
			lpTokenAddress
		) = IWhitelistedPTokenEmission(_whitelistedPTokenEmissionContract)
			.calculateAllPendingHolderRewards(holderAddress);

		if (
			holderAddress == address(0) ||
			lpTokenAddress == address(0) ||
			accountAddress == address(0)
		) {
			return (
				rewardAmounts,
				rewardTokens,
				sTokenAddresses,
				lpTokenAddress,
				updatedSupplyLPTimeshare,
				newSupplyLPTimeShare
			);
		}

		// calculate the new LPTimeShare of the user's LP Token
		_userLPTimeShare = (
			(_lpBalance[lpTokenAddress][accountAddress]).mul(
				block.timestamp.sub(
					_lastLiquidityTimestamp[lpTokenAddress][accountAddress]
				)
			)
		);

		// calculate the new LPTimeShare of the sum of supply of all LP Tokens
		newSupplyLPTimeShare = (
			(_lpSupply[lpTokenAddress]).mul(
				block.timestamp.sub(
					IWhitelistedRewardEmission(
						_whitelistedRewardEmissionContract
					).getLastLPTimeShareTimestamp(lpTokenAddress)
				)
			)
		);

		// calculate the totalSupplyLPTimeShare by adding new LPTimeShare to the existing share
		_totalSupplyLPTimeShare = _lastLPTimeShare[lpTokenAddress].add(
			newSupplyLPTimeShare
		);

		// calculate the remaining LPTimeShare of the total supply after the tokens for the user has been dispatched
		updatedSupplyLPTimeshare = _totalSupplyLPTimeShare.sub(
			_userLPTimeShare
		);

		// calculate the amounts and token contracts of other reward tokens
		(
			uint256[] memory otherRewardAmounts,
			address[] memory otherRewardTokens
		) = IWhitelistedRewardEmission(_whitelistedRewardEmissionContract)
				.calculateOtherPendingRewards(
					holderAddress,
					lpTokenAddress,
					accountAddress,
					_userLPTimeShare,
					newSupplyLPTimeShare
				);

		(rewardAmounts, rewardTokens) = _getRewardData(
			holderAddress,
			sTokenAddresses,
			holderRewards,
			_userLPTimeShare,
			_totalSupplyLPTimeShare,
			otherRewardAmounts,
			otherRewardTokens
		);
	}

	/*
	 * @dev get liquidity and reward tokens and disburse to user
	 * @param holderAddress: holder contract address
	 * @param sTokenAddresses: sToken contract address in array
	 * @param holderRewards: holder contract address in array
	 * @param userLPTimeShare: user LP timeshare
	 * @param totalSupplyLPTimeShare: total supply LP timeshare
	 * @param otherRewardAmounts: reward amount in array
	 * @param otherRewardTokens: reward tokens in array
	 */
	function _getRewardData(
		address holderAddress,
		address[] memory sTokenAddresses,
		uint256[] memory holderRewards,
		uint256 userLPTimeShare,
		uint256 totalSupplyLPTimeShare,
		uint256[] memory otherRewardAmounts,
		address[] memory otherRewardTokens
	)
		internal
		view
		returns (uint256[] memory rewardAmounts, address[] memory rewardTokens)
	{
		uint256 i;
		uint256 rewardPool;

		// initialize rewardAmounts and rewardTokens as per the sum of the size of pSTAKE and other rewards
		rewardAmounts = new uint256[](
			(otherRewardAmounts.length).add(sTokenAddresses.length)
		);
		rewardTokens = new address[](
			(otherRewardTokens.length).add(sTokenAddresses.length)
		);

		// CALCULATE REWARD FOR EACH UTOKEN ADDRESS
		for (i = 0; i < sTokenAddresses.length; i = i.add(1)) {
			rewardTokens[i] = ISTokensV2(sTokenAddresses[i]).getUTokenAddress();
			// uTokenAddress = ISTokensV2(sTokenAddresses[i]).getUTokenAddress();
			if (totalSupplyLPTimeShare > 0) {
				// calculated the updated rewardPool
				rewardPool = IUTokensV2(rewardTokens[i]).balanceOf(
					holderAddress
				);
				rewardPool = rewardPool.add(holderRewards[i]);
				// calculate the reward portion of the user
				rewardAmounts[i] = rewardPool.mulDiv(
					userLPTimeShare,
					totalSupplyLPTimeShare
				);
			}
		}

		for (i = 0; i < otherRewardAmounts.length; i = i.add(1)) {
			rewardTokens[i.add(sTokenAddresses.length)] = otherRewardTokens[i];
			rewardAmounts[i.add(sTokenAddresses.length)] = otherRewardAmounts[
				i
			];
		}
	}

	/*
	 * @dev calculate reward tokens and disburse to user
	 * @param holderAddress: holder contract address
	 * @param accountAddress: user address
	 */
	function _calculateRewards(address holderAddress, address accountAddress)
		internal
		returns (
			uint256[] memory RewardAmounts,
			address[] memory RewardTokens,
			address[] memory sTokenAddresses,
			address lpTokenAddress
		)
	{
		uint256 updatedSupplyLPTimeshare;
		uint256 newSupplyLPTimeShare;
		uint256 i;

		(
			RewardAmounts,
			RewardTokens,
			sTokenAddresses,
			lpTokenAddress,
			updatedSupplyLPTimeshare,
			newSupplyLPTimeShare
		) = calculatePendingRewards(holderAddress, accountAddress);

		// update last timestamps and LPTimeShares as per Checks-Effects-Interactions pattern
		_lastLiquidityTimestamp[lpTokenAddress][accountAddress] = block
			.timestamp;

		_lastLPTimeShare[lpTokenAddress] = updatedSupplyLPTimeshare;

		// update the cummulative new supply LP Timeshare value
		IWhitelistedRewardEmission(_whitelistedRewardEmissionContract)
			.setLastCummulativeSupplyLPTimeShare(
				lpTokenAddress,
				newSupplyLPTimeShare
			);

		// update the _lastLPTimeShareTimestampArray
		IWhitelistedRewardEmission(_whitelistedRewardEmissionContract)
			.setLastLPTimeShareTimestamp(lpTokenAddress, block.timestamp);

		// DISBURSE THE MULTIPLE UTOKEN REWARDS TO USER (transfer)
		for (i = 0; i < sTokenAddresses.length; i = i.add(1)) {
			if (RewardAmounts[i] > 0)
				IHolderV2(holderAddress).safeTransfer(
					RewardTokens[i],
					accountAddress,
					RewardAmounts[i]
				);
		}

		// DISBURSE THE OTHER REWARD TOKENS TO USER (transfer)
		for (
			i = sTokenAddresses.length;
			i < RewardTokens.length;
			i = i.add(1)
		) {

			IWhitelistedRewardEmission(_whitelistedRewardEmissionContract)
				.setRewardPoolUserTimestamp(
					holderAddress,
					RewardTokens[i],
					accountAddress,
					block.timestamp
				);

			// dispatch the rewards for that specific token
			if (RewardAmounts[i] > 0) {
				IHolderV2(holderAddress).safeTransfer(
					RewardTokens[i],
					accountAddress,
					RewardAmounts[i]
				);
			}
		}

		emit CalculateRewardsStakeLP(
			holderAddress,
			lpTokenAddress,
			accountAddress,
			RewardAmounts,
			RewardTokens,
			sTokenAddresses,
			block.timestamp
		);
	}

	/*
	 * @dev calculate liquidity and reward tokens and disburse to user
	 * @param holderAddress: holder contract address
	 */
	function calculateSyncedRewards(address holderAddress)
		public
		virtual
		override
		whenNotPaused
		returns (
			uint256[] memory RewardAmounts,
			address[] memory RewardTokens,
			address[] memory sTokenAddresses,
			address lpTokenAddress
		)
	{
		// check for validity of arguments
		require(holderAddress != address(0), "LP1");

		// initiate calculateHolderRewards for all StokenAddress-whitelistedAddress pair that
		// comes under the holder contract
		IWhitelistedPTokenEmission(_whitelistedPTokenEmissionContract)
			.calculateAllHolderRewards(holderAddress);

		// now initiate the calculate Rewards to distribute to the user
		// calculate liquidity and reward tokens and disburse to user
		(
			RewardAmounts,
			RewardTokens,
			sTokenAddresses,
			lpTokenAddress
		) = _calculateRewards(holderAddress, _msgSender());

		require(lpTokenAddress != address(0), "LP2");

		emit TriggeredCalculateSyncedRewards(
			holderAddress,
			_msgSender(),
			RewardAmounts,
			RewardTokens,
			sTokenAddresses,
			block.timestamp
		);
	}

	/*
	 * @dev adding the liquidity
	 * @param holderAddress: holder contract address
	 * @param amount: token amount
	 *
	 * Emits a {AddLiquidity} event with 'lpToken, amount, rewards and liquidity'
	 *
	 */
	function addLiquidity(address holderAddress, uint256 amount)
		public
		virtual
		override
		whenNotPaused
		returns (bool success)
	{
		// directly call calculate Synced Rewards since all the require conditions are checked there
		(, , , address lpTokenAddress) = calculateSyncedRewards(holderAddress);
		address messageSender = _msgSender();

		// update the user balance
		_lpBalance[lpTokenAddress][messageSender] = _lpBalance[lpTokenAddress][
			messageSender
		].add(amount);

		// update the supply of lp tokens for reward and liquidity calculation
		_lpSupply[lpTokenAddress] = _lpSupply[lpTokenAddress].add(amount);

		// finally transfer the new LP Tokens to the StakeLP contract as per Checks-Effects-Interactions pattern
		TransferHelper.safeTransferFrom(
			lpTokenAddress,
			messageSender,
			address(this),
			amount
		);

		// emit an event
		emit AddLiquidity(
			holderAddress,
			messageSender,
			amount,
			block.timestamp
		);

		success = true;
		return success;
	}

	/*
	 * @dev removing the liquidity
	 * @param holderAddress: holder contract address
	 * @param amount: token amount
	 *
	 * Emits a {RemoveLiquidity} event with 'lpToken, amount, rewards and liquidity'
	 *
	 */
	function removeLiquidity(address holderAddress, uint256 amount)
		public
		virtual
		override
		whenNotPaused
		nonReentrant
		returns (bool success)
	{
		// directly call calculateSyncedRewards since all the require conditions are checked there
		(, , , address lpTokenAddress) = calculateSyncedRewards(holderAddress);
		address messageSender = _msgSender();

		// check if suffecient balance is there
		require(_lpBalance[lpTokenAddress][messageSender] >= amount, "LP3");

		// update the user balance
		_lpBalance[lpTokenAddress][messageSender] = _lpBalance[lpTokenAddress][
			messageSender
		].sub(amount);

		// update the supply of lp tokens for reward and liquidity calculation
		_lpSupply[lpTokenAddress] = _lpSupply[lpTokenAddress].sub(amount);

		// finally transfer the LP Tokens to the user as per Checks-Effects-Interactions pattern
		TransferHelper.safeTransfer(lpTokenAddress, messageSender, amount);

		emit RemoveLiquidity(
			holderAddress,
			messageSender,
			amount,
			block.timestamp
		);

		success = true;
		return success;
	}

	/**
	 * @dev Set 'WhitelistedPTokenEmissionContract', called from constructor
	 *
	 * Emits a {SetWhitelistedPTokenEmissionContract} event with '_contract' set to the whitelistedPTokenEmission contract address.
	 *
	 */
	function setWhitelistedPTokenEmissionContract(
		address whitelistedPTokenEmissionContract
	) public virtual override {
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "LP4");
		_whitelistedPTokenEmissionContract = whitelistedPTokenEmissionContract;
		emit SetWhitelistedPTokenEmissionContract(
			whitelistedPTokenEmissionContract
		);
	}

	/**
	 * @dev Set 'whitelistedRewardEmissionContract', called from constructor
	 *
	 * Emits a {SetWhitelistedRewardEmissionContract} event with '_contract' set to the whitelistedRewardEmission contract address.
	 *
	 */
	function setWhitelistedRewardEmissionContract(
		address whitelistedRewardEmissionContract
	) public virtual override {
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "LP5");
		_whitelistedRewardEmissionContract = whitelistedRewardEmissionContract;
		emit SetWhitelistedRewardEmissionContract(
			whitelistedRewardEmissionContract
		);
	}

	/**
	 * @dev Triggers stopped state.
	 *
	 * Requirements:
	 *
	 * - The contract must not be paused.
	 */
	function pause() public virtual override returns (bool success) {
		require(hasRole(PAUSER_ROLE, _msgSender()), "LP6");
		_pause();
		return true;
	}

	/**
	 * @dev Returns to normal state.
	 *
	 * Requirements:
	 *
	 * - The contract must be paused.
	 */
	function unpause() public virtual override returns (bool success) {
		require(hasRole(PAUSER_ROLE, _msgSender()), "LP7");
		_unpause();
		return true;
	}
}
