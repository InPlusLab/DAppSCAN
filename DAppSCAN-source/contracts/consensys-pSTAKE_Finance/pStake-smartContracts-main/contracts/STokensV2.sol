/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/ISTokensV2.sol";
import "./interfaces/IUTokensV2.sol";
import "./interfaces/IHolderV2.sol";
import "./libraries/FullMath.sol";

contract STokensV2 is
	ERC20Upgradeable,
	ISTokensV2,
	PausableUpgradeable,
	AccessControlUpgradeable
{
	using SafeMathUpgradeable for uint256;
	using FullMath for uint256;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	// constants defining access control ROLES
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

	// variables pertaining to holder logic for whitelisted addresses & StakeLP
	// deposit contract address for STokens in a DeFi product
	EnumerableSetUpgradeable.AddressSet private _whitelistedAddresses;
	// Holder contract address for this whitelisted contract. Many can point to one Holder contract
	mapping(address => address) public _holderContractAddress;
	// LP Token contract address which might be different from whitelisted contract
	mapping(address => address) public _lpContractAddress;
	// last timestamp when the holder reward calculation was performed for updating reward pool
	mapping(address => uint256) public _lastHolderRewardTimestamp;

	// _liquidStakingContract address does the mint and burn of STokens
	address public _liquidStakingContract;
	// _uTokens variable is used to do mint of UTokens
	IUTokensV2 public _uTokens;

	// variables pertaining to moving reward rate logic
	uint256[] private _rewardRate;
	uint256[] private _lastMovingRewardTimestamp;
	uint256 public _valueDivisor;
	mapping(address => uint256) public _lastUserRewardTimestamp;

	// variable pertaining to contract upgrades versioning
	uint256 public _version;
	// required to store the whitelisting holder logic data initiated from WhitelistedEmission contract
	address public _whitelistedPTokenEmissionContract;

	/**
	 * @dev Constructor for initializing the SToken contract.
	 * @param uaddress - address of the UToken contract.
	 * @param pauserAddress - address of the pauser admin.
	 * @param rewardRate - set to rewardRate * 10^-5
	 * @param valueDivisor - valueDivisor set to 10^9.
	 */
	function initialize(
		address uaddress,
		address pauserAddress,
		uint256 rewardRate,
		uint256 valueDivisor
	) public virtual initializer {
		__ERC20_init("pSTAKE Staked ATOM", "stkATOM");
		__AccessControl_init();
		__Pausable_init();
		_setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
		_setupRole(PAUSER_ROLE, pauserAddress);
		setUTokensContract(uaddress);
		_valueDivisor = valueDivisor;
		require(rewardRate <= _valueDivisor.mul(100), "ST1");
		_rewardRate.push(rewardRate);
		_lastMovingRewardTimestamp.push(block.timestamp);
		_setupDecimals(6);
	}

	/**
	 * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
	 * @param whitelistedAddress: whitelisted contract address
	 */
	function isContractWhitelisted(address whitelistedAddress)
		public
		view
		virtual
		override
		returns (bool result)
	{
		result = _whitelistedAddresses.contains(whitelistedAddress);
		return result;
	}

	/**
	 * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
	 * @param whitelistedAddress: contract address
	 */
	function getWhitelistData(address whitelistedAddress)
		public
		view
		virtual
		override
		returns (
			address holderAddress,
			address lpAddress,
			address uTokenAddress,
			uint256 lastHolderRewardTimestamp
		)
	{
		// Get the time in number of blocks
		holderAddress = _holderContractAddress[whitelistedAddress];
		lpAddress = _lpContractAddress[whitelistedAddress];
		lastHolderRewardTimestamp = _lastHolderRewardTimestamp[
			whitelistedAddress
		];
		uTokenAddress = (holderAddress == address(0) || lpAddress == address(0))
			? address(0)
			: address(_uTokens);
	}

	/**
	 * @dev get uToken address
	 */
	function getUTokenAddress()
		public
		view
		virtual
		override
		returns (address uTokenAddress)
	{
		uTokenAddress = address(_uTokens);
	}

	/*
	 * @dev set reward rate called by admin
	 * @param rewardRate: reward rate
	 *
	 *
	 * Requirements:
	 *
	 * - `rate` cannot be less than or equal to zero.
	 *
	 */
	function setRewardRate(uint256 rewardRate)
		public
		virtual
		override
		returns (bool success)
	{
		// range checks for rewardRate. Since rewardRate cannot be more than 100%, the max cap
		// is _valueDivisor * 100, which then brings the fees to 100 (percentage)
		require(rewardRate <= _valueDivisor.mul(100), "ST18");
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ST2");
		_rewardRate.push(rewardRate);
		_lastMovingRewardTimestamp.push(block.timestamp);
		emit SetRewardRate(rewardRate);

		return true;
	}

	/**
	 * @dev get reward rate, last moving reward timestamp and value divisor
	 */
	function getRewardRate()
		public
		view
		virtual
		override
		returns (
			uint256[] memory rewardRate,
			uint256[] memory lastMovingRewardTimestamp,
			uint256 valueDivisor
		)
	{
		rewardRate = _rewardRate;
		lastMovingRewardTimestamp = _lastMovingRewardTimestamp;
		valueDivisor = _valueDivisor;
	}

	/**
	 * @dev Mint new stokens for the provided 'address' and 'tokens'
	 * @param to: account address, tokens: number of tokens
	 *
	 * Emits a {MintTokens} event with 'to' set to address and 'tokens' set to amount of tokens.
	 *
	 * Requirements:
	 *
	 * - `amount` cannot be less than zero.
	 *
	 */
	function mint(address to, uint256 tokens)
		public
		virtual
		override
		returns (bool)
	{
		require(_msgSender() == _liquidStakingContract, "ST3");
		_mint(to, tokens);
		return true;
	}

	/*
	 * @dev Burn stokens for the provided 'address' and 'tokens'
	 * @param to: account address, tokens: number of tokens
	 *
	 * Emits a {BurnTokens} event with 'to' set to address and 'tokens' set to amount of tokens.
	 *
	 * Requirements:
	 *
	 * - `amount` cannot be less than zero.
	 *
	 */
	function burn(address from, uint256 tokens)
		public
		virtual
		override
		returns (bool)
	{
		require(_msgSender() == _liquidStakingContract, "ST4");
		_burn(from, tokens);
		return true;
	}

	/**
	 * @dev Calculate pending rewards from the provided 'principal' & 'lastRewardTimestamp'. The rate is the moving reward rate.
	 * @param principal: principal amount
	 * @param lastRewardTimestamp: timestamp of last reward calculation performed
	 */
	function _calculatePendingRewards(
		uint256 principal,
		uint256 lastRewardTimestamp
	) internal view returns (uint256 pendingRewards) {
		uint256 _index;
		uint256 _rewardBlocks;
		uint256 _simpleInterestOfInterval;
		uint256 _temp;
		// return 0 if principal or timeperiod is zero
		if (principal == 0 || block.timestamp.sub(lastRewardTimestamp) == 0)
			return 0;
		// calculate rewards for each interval period between rewardRate changes
		uint256 _lastMovingRewardLength = _lastMovingRewardTimestamp.length.sub(
			1
		);
		// SWC-128-DoS With Block Gas Limit: L249
		for (_index = _lastMovingRewardLength; _index >= 0; ) {
			// logic applies for all indexes of array except last index
			if (_index < _lastMovingRewardTimestamp.length.sub(1)) {
				if (_lastMovingRewardTimestamp[_index] > lastRewardTimestamp) {
					_rewardBlocks = (_lastMovingRewardTimestamp[_index.add(1)])
						.sub(_lastMovingRewardTimestamp[_index]);
					_temp = principal.mulDiv(_rewardRate[_index], 100);
					_simpleInterestOfInterval = _temp.mulDiv(
						_rewardBlocks,
						_valueDivisor
					);
					pendingRewards = pendingRewards.add(
						_simpleInterestOfInterval
					);
				} else {
					_rewardBlocks = (_lastMovingRewardTimestamp[_index.add(1)])
						.sub(lastRewardTimestamp);
					_temp = principal.mulDiv(_rewardRate[_index], 100);
					_simpleInterestOfInterval = _temp.mulDiv(
						_rewardBlocks,
						_valueDivisor
					);
					pendingRewards = pendingRewards.add(
						_simpleInterestOfInterval
					);
					break;
				}
			}
			// logic applies only for the last index of array
			else {
				if (_lastMovingRewardTimestamp[_index] > lastRewardTimestamp) {
					_rewardBlocks = (block.timestamp).sub(
						_lastMovingRewardTimestamp[_index]
					);
					_temp = principal.mulDiv(_rewardRate[_index], 100);
					_simpleInterestOfInterval = _temp.mulDiv(
						_rewardBlocks,
						_valueDivisor
					);
					pendingRewards = pendingRewards.add(
						_simpleInterestOfInterval
					);
				} else {
					_rewardBlocks = (block.timestamp).sub(lastRewardTimestamp);
					_temp = principal.mulDiv(_rewardRate[_index], 100);
					_simpleInterestOfInterval = _temp.mulDiv(
						_rewardBlocks,
						_valueDivisor
					);
					pendingRewards = pendingRewards.add(
						_simpleInterestOfInterval
					);
					break;
				}
			}

			if (_index == 0) break;
			else {
				_index = _index.sub(1);
			}
		}
		return pendingRewards;
	}

	/**
	 * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
	 * @param to: account address
	 */
	function calculatePendingRewards(address to)
		public
		view
		virtual
		override
		returns (uint256 pendingRewards)
	{
		// Get the time in number of blocks
		uint256 _lastRewardTimestamp = _lastUserRewardTimestamp[to];
		// Get the balance of the account
		uint256 _balance = balanceOf(to);
		// calculate pending rewards using _calculatePendingRewards
		pendingRewards = _calculatePendingRewards(
			_balance,
			_lastRewardTimestamp
		);

		return pendingRewards;
	}

	/**
	 * @dev Calculate rewards for the provided 'address'
	 * @param to: account address
	 */
	function _calculateRewards(address to) internal returns (uint256 _reward) {
		// keep an if condition to check for address(0), instead of require condition, because address(0) is
		// a valid condition when it is a mint/burn operation
		if (to != address(0)) {
			// Calculate the rewards pending
			_reward = calculatePendingRewards(to);

			// Set the new stakedBlock to the current,
			// as per Checks-Effects-Interactions pattern
			_lastUserRewardTimestamp[to] = block.timestamp;

			// mint uTokens only if reward is greater than zero
			if (_reward > 0) {
				// Mint new uTokens and send to the callers account
				_uTokens.mint(to, _reward);
				emit CalculateRewards(to, _reward, block.timestamp);
			}
		}
		return _reward;
	}

	/**
	 * @dev Calculate rewards for the provided 'address'
	 * @param to: account address
	 *
	 * Emits a {TriggeredCalculateRewards} event with 'to' set to address, 'reward' set to amount of tokens and 'timestamp'
	 *
	 */
	function calculateRewards(address to)
		public
		virtual
		override
		whenNotPaused
		returns (uint256 reward)
	{
		bool isContractWhitelistedLocal = _whitelistedAddresses.contains(to);
		require(to == _msgSender() && !isContractWhitelistedLocal, "ST5");
		reward = _calculateRewards(to);
		emit TriggeredCalculateRewards(to, reward, block.timestamp);
		return reward;
	}

	/**
	 * @dev Calculate rewards for the provided 'holder address'
	 * @param to: holder address
	 */
	function _calculateHolderRewards(address to)
		internal
		returns (
			uint256 rewards,
			address holderAddress,
			address lpTokenAddress
		)
	{
		require(
			_whitelistedAddresses.contains(to) &&
				_holderContractAddress[to] != address(0) &&
				_lpContractAddress[to] != address(0),
			"ST6"
		);

		(
			rewards,
			holderAddress,
			lpTokenAddress
		) = calculatePendingHolderRewards(to);

		// update the last timestamp of reward pool to the current time as per Checks-Effects-Interactions pattern
		_lastHolderRewardTimestamp[to] = block.timestamp;

		// Mint new uTokens and send to the holder contract account as updated reward pool
		if (rewards > 0) {
			_uTokens.mint(holderAddress, rewards);
		}

		emit CalculateHolderRewards(
			to,
			address(this),
			rewards,
			block.timestamp
		);
	}

	/**
	 * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
	 * @param to: account address
	 */
	function calculatePendingHolderRewards(address to)
		public
		view
		virtual
		override
		returns (
			uint256 pendingRewards,
			address holderAddress,
			address lpAddress
		)
	{
		// holderContract and lpContract (lp token contract) need to be validated together because
		// it might not be practical to setup holder to collect reward pool but not StakeLP to distribute reward
		// since the reward distribution calculation starts the minute reward pool is created
		if (
			_whitelistedAddresses.contains(to) &&
			_holderContractAddress[to] != address(0) &&
			_lpContractAddress[to] != address(0)
		) {
			uint256 _sTokenSupply = IHolderV2(_holderContractAddress[to])
				.getSTokenSupply(to, address(this));

			// calculate the reward applying the moving reward rate
			if (_sTokenSupply > 0) {
				pendingRewards = _calculatePendingRewards(
					_sTokenSupply,
					_lastHolderRewardTimestamp[to]
				);
				holderAddress = _holderContractAddress[to];
				lpAddress = _lpContractAddress[to];
			}
		}
	}

	/**
	 * @dev Calculate rewards for the provided 'address'
	 * @param to: account address
	 *
	 * Emits a {TriggeredCalculateRewards} event with 'to' set to address, 'reward' set to amount of tokens and 'timestamp'
	 *
	 */
	function calculateHolderRewards(address to)
		public
		virtual
		override
		whenNotPaused
		returns (
			uint256 rewards,
			address holderAddress,
			address lpTokenAddress
		)
	{
		(rewards, holderAddress, lpTokenAddress) = _calculateHolderRewards(to);
		emit TriggeredCalculateHolderRewards(
			to,
			address(this),
			rewards,
			block.timestamp
		);
	}

	/**
	 * @dev Hook that is called before any transfer of tokens. This includes
	 * minting and burning.
	 *
	 * Calling conditions:
	 *
	 * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
	 * will be to transferred to `to`.
	 * - when `from` is zero, `amount` tokens will be minted for `to`.
	 * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
	 * - `from` and `to` are never both zero.
	 *
	 */
	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 amount
	) internal virtual override {
		require(!paused(), "ST7");
		super._beforeTokenTransfer(from, to, amount);
		bool isFromContractWhitelisted = isContractWhitelisted(from);
		bool isToContractWhitelisted = isContractWhitelisted(to);

		if (!isFromContractWhitelisted) {
			_calculateRewards(from);
			if (!isToContractWhitelisted) {
				_calculateRewards(to);
			} else {
				_calculateHolderRewards(to);
			}
		} else {
			_calculateHolderRewards(from);
			if (!isToContractWhitelisted) {
				_calculateRewards(to);
			} else {
				_calculateHolderRewards(to);
			}
		}
	}

	/*
	 * @dev Set 'contract address', called from constructor
	 * @param whitelistedPTokenEmissionContract: whitelistedPTokenEmission contract address
	 *
	 * Emits a {SetWhitelistedPTokenEmissionContract} event with '_contract' set to the WhitelistedPTokenEmission contract address.
	 *
	 */
	function setWhitelistedPTokenEmissionContract(
		address whitelistedPTokenEmissionContract
	) public virtual override {
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ST11");
		_whitelistedPTokenEmissionContract = whitelistedPTokenEmissionContract;
		emit SetWhitelistedPTokenEmissionContract(
			whitelistedPTokenEmissionContract
		);
	}

	/*
    * @dev Set 'whitelisted address', performed by admin only
    * @param whitelistedAddress: contract address of the whitelisted party
    * @param holderContractAddress: holder contract address
    * @param lpContractAddress: LP token contract address
    *
    * Emits a {setWhitelistedAddress} event
    *
    */
	function setWhitelistedAddress(
		address whitelistedAddress,
		address holderContractAddress,
		address lpContractAddress
	) public virtual override returns (bool success) {
		require(_msgSender() == _whitelistedPTokenEmissionContract, "ST12");
		// lpTokenERC20ContractAddress or sTokenReserveContractAddress can be address(0) but not whitelistedAddress
		require(whitelistedAddress != address(0), "ST13");
		// add the whitelistedAddress if it isn't already available
		if (!_whitelistedAddresses.contains(whitelistedAddress))
			_whitelistedAddresses.add(whitelistedAddress);
		// add the contract addresses to holder mapping variable
		_holderContractAddress[whitelistedAddress] = holderContractAddress;
		_lpContractAddress[whitelistedAddress] = lpContractAddress;

		emit SetWhitelistedAddress(
			whitelistedAddress,
			holderContractAddress,
			lpContractAddress,
			block.timestamp
		);
		success = true;
		return success;
	}

	/*
	 * @dev remove 'whitelisted address', performed by admin only
	 * @param whitelistedAddress: contract address of the whitelisted party
	 *
	 * Emits a {RemoveWhitelistedAddress} event
	 *
	 */
	function removeWhitelistedAddress(address whitelistedAddress)
		public
		virtual
		override
		returns (bool success)
	{
		require(_msgSender() == _whitelistedPTokenEmissionContract, "ST14");
		require(whitelistedAddress != address(0), "ST15");
		// remove whitelistedAddress from the list
		_whitelistedAddresses.remove(whitelistedAddress);

		// emit an event
		emit RemoveWhitelistedAddress(
			whitelistedAddress,
			_holderContractAddress[whitelistedAddress],
			_lpContractAddress[whitelistedAddress],
			_lastHolderRewardTimestamp[whitelistedAddress],
			block.timestamp
		);

		// delete holder contract values
		delete _holderContractAddress[whitelistedAddress];
		delete _lpContractAddress[whitelistedAddress];
		delete _lastHolderRewardTimestamp[whitelistedAddress];

		success = true;
		return success;
	}

	/*
	 * @dev Set 'contract address', called from constructor
	 * @param uTokenContract: utoken contract address
	 *
	 * Emits a {SetUTokensContract} event with '_contract' set to the utoken contract address.
	 *
	 */
	function setUTokensContract(address uTokenContract)
		public
		virtual
		override
	{
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ST8");
		_uTokens = IUTokensV2(uTokenContract);
		emit SetUTokensContract(uTokenContract);
	}

	/*
	 * @dev Set 'contract address', called from constructor
	 * @param liquidStakingContract: liquidStaking contract address
	 *
	 * Emits a {SetLiquidStakingContract} event with '_contract' set to the liquidStaking contract address.
	 *
	 */
	function setLiquidStakingContract(address liquidStakingContract)
		public
		virtual
		override
	{
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ST9");
		_liquidStakingContract = liquidStakingContract;
		emit SetLiquidStakingContract(liquidStakingContract);
	}

	/**
	 * @dev Triggers stopped state.
	 *
	 * Requirements:
	 *
	 * - The contract must not be paused.
	 */
	function pause() public virtual override returns (bool success) {
		require(hasRole(PAUSER_ROLE, _msgSender()), "ST16");
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
		require(hasRole(PAUSER_ROLE, _msgSender()), "ST17");
		_unpause();
		return true;
	}
}
