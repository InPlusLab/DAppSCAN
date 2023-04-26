// SPDX-License-Identifier: MIT

/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/

* Based on Synthetix Staking Rewards contract
* Synthetix: StakingRewards.sol
*
* Latest source (may be newer): https://github.com/Synthetixio/synthetix/blob/v2.37.0/contracts/StakingRewards.sol
* Docs: https://docs.synthetix.io/contracts/source/contracts/StakingRewards/
*/

pragma solidity 0.7.5;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract RewardHandler is Ownable, AccessControl, ReentrancyGuard, Pausable {
	/// @notice Open Zeppelin libraries
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	/// @notice Address of the reward
	IERC20 public immutable rewardsToken;

	/// @notice Address of the vault
	address public immutable vault;

	/// @notice Tracks the period where users stop earning rewards
	uint256 public periodFinish = 0;

	uint256 public rewardRate = 0;

	/// @notice How long the rewards last, it updates when more rewards are added
	uint256 public rewardsDuration = 14 days;

	/// @notice Last time rewards were updated
	uint256 public lastUpdateTime;

	uint256 public rewardPerTokenStored;

	/// @notice Track the rewards paid to users
	mapping(address => uint256) public userRewardPerTokenPaid;

	/// @notice Tracks the user rewards
	mapping(address => uint256) public rewards;

	/// @dev Tracks the total supply of the minted TCAPs
	uint256 private _totalSupply;

	/// @dev Tracks the amount of TCAP minted per user
	mapping(address => uint256) private _balances;

	/// @notice An event emitted when a reward is added
	event RewardAdded(uint256 reward);

	/// @notice An event emitted when TCAP is minted and staked to earn rewards
	event Staked(address indexed user, uint256 amount);

	/// @notice An event emitted when TCAP is burned and removed of stake
	event Withdrawn(address indexed user, uint256 amount);

	/// @notice An event emitted when reward is paid to a user
	event RewardPaid(address indexed user, uint256 reward);

	/// @notice An event emitted when the rewards duration is updated
	event RewardsDurationUpdated(uint256 newDuration);

	/// @notice An event emitted when a erc20 token is recovered
	event Recovered(address token, uint256 amount);

	/**
	 * @notice Constructor
   * @param _owner address
   * @param _rewardsToken address
   * @param _vault uint256
   */
	constructor(
		address _owner,
		address _rewardsToken,
		address _vault
	) {
		require(
			_owner != address(0) &&
			_rewardsToken != address(0) &&
			_vault != address(0),
			"RewardHandler::constructor: address can't be zero"
		);

		rewardsToken = IERC20(_rewardsToken);
		vault = _vault;
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		transferOwnership(_owner);
	}

	/**
	 * @notice Updates the reward and time on call.
   * @param _account address
   */
	modifier updateReward(address _account) {
		rewardPerTokenStored = rewardPerToken();
		lastUpdateTime = lastTimeRewardApplicable();

		if (_account != address(0)) {
			rewards[_account] = earned(_account);
			userRewardPerTokenPaid[_account] = rewardPerTokenStored;
		}
		_;
	}

	/// @notice Reverts if the caller is not a vault.
	modifier onlyVault() {
		require(
			msg.sender == vault,
			"RewardHandler::OnlyVault: not calling from vault"
		);
		_;
	}

	/// @notice Returns the total amount of TCAP tokens minted and getting reward on this vault.
	function totalSupply() external view returns (uint256) {
		return _totalSupply;
	}

	/**
	 * @notice Returns the amount of TCAP tokens minted and getting reward from specific user.
   * @param _account address
   */
	function balanceOf(address _account) external view returns (uint256) {
		return _balances[_account];
	}

	/// @notice Returns the Reward rate multiplied by the rewards duration time.
	function getRewardForDuration() external view returns (uint256) {
		return rewardRate.mul(rewardsDuration);
	}

	/**
	 * @notice Called when TCAP is minted, adds the minted value as stake
   * @param _staker address
   * @param _amount uint
   * @dev Only vault can call it
   * @dev Updates rewards on call
   */
	function stake(address _staker, uint256 _amount)
	external
	onlyVault
	nonReentrant
	whenNotPaused
	updateReward(_staker)
	{
		require(_amount > 0, "Cannot stake 0");
		_totalSupply = _totalSupply.add(_amount);
		_balances[_staker] = _balances[_staker].add(_amount);
		emit Staked(_staker, _amount);
	}

	/**
	 * @notice Removes all stake and transfers all rewards to the staker.
   * @param _staker address
   * @dev Only vault can call it
   */
	function exit(address _staker) external onlyVault {
		withdraw(_staker, _balances[_staker]);
		getRewardFromVault(_staker);
	}

	/**
	 * @notice Notifies the contract that reward has been added to be given.
   * @param _reward uint
   * @dev Only owner  can call it
   * @dev Increases duration of rewards
   */
	function notifyRewardAmount(uint256 _reward)
	external
	onlyOwner
	updateReward(address(0))
	{
		if (block.timestamp >= periodFinish) {
			rewardRate = _reward.div(rewardsDuration);
		} else {
			uint256 remaining = periodFinish.sub(block.timestamp);
			uint256 leftover = remaining.mul(rewardRate);
			rewardRate = _reward.add(leftover).div(rewardsDuration);
		}

		// Ensure the provided reward amount is not more than the balance in the contract.
		// This keeps the reward rate in the right range, preventing overflows due to
		// very high values of rewardRate in the earned and rewardsPerToken functions;
		// Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
		uint256 balance = rewardsToken.balanceOf(address(this));
		require(
			rewardRate <= balance.div(rewardsDuration),
			"Provided reward too high"
		);

		lastUpdateTime = block.timestamp;
		periodFinish = block.timestamp.add(rewardsDuration);
		emit RewardAdded(_reward);
	}

	/**
	 * @notice Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
   * @param _tokenAddress address
   * @param _tokenAmount uint
   * @dev Only owner  can call it
   */
	function recoverERC20(address _tokenAddress, uint256 _tokenAmount)
	external
	onlyOwner
	{
		// Cannot recover the staking token or the rewards token
		require(
			_tokenAddress != address(rewardsToken),
			"Cannot withdraw the staking or rewards tokens"
		);
		IERC20(_tokenAddress).safeTransfer(owner(), _tokenAmount);
		emit Recovered(_tokenAddress, _tokenAmount);
	}

	/**
	 * @notice  Updates the reward duration
   * @param _rewardsDuration uint
   * @dev Only owner  can call it
   * @dev Previous rewards must be complete
   */
	function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
		require(
			block.timestamp > periodFinish,
			"Previous rewards period must be complete before changing the duration for the new period"
		);
		rewardsDuration = _rewardsDuration;
		emit RewardsDurationUpdated(rewardsDuration);
	}

	/// @notice Returns the minimun between current block timestamp or the finish period of rewards.
	function lastTimeRewardApplicable() public view returns (uint256) {
		return min(block.timestamp, periodFinish);
	}

	/// @notice Returns the calculated reward per token deposited.
	function rewardPerToken() public view returns (uint256) {
		if (_totalSupply == 0) {
			return rewardPerTokenStored;
		}

		return
		rewardPerTokenStored.add(
			lastTimeRewardApplicable()
			.sub(lastUpdateTime)
			.mul(rewardRate)
			.mul(1e18)
			.div(_totalSupply)
		);
	}

	/**
	 * @notice Returns the amount of reward tokens a user has earned.
   * @param _account address
   */
	function earned(address _account) public view returns (uint256) {
		return
		_balances[_account]
		.mul(rewardPerToken().sub(userRewardPerTokenPaid[_account]))
		.div(1e18)
		.add(rewards[_account]);
	}

	/**
	 * @notice Returns the minimun between two variables
   * @param _a uint
   * @param _b uint
   */
	function min(uint256 _a, uint256 _b) public pure returns (uint256) {
		return _a < _b ? _a : _b;
	}

	/**
	 * @notice Called when TCAP is burned or liquidated, removes the burned value as stake
   * @param _staker address
   * @param _amount uint
   * @dev Only vault can call it
   * @dev Updates rewards on call
   */
	function withdraw(address _staker, uint256 _amount)
	public
	onlyVault
	nonReentrant
	updateReward(_staker)
	{
		require(_amount > 0, "Cannot withdraw 0");
		_totalSupply = _totalSupply.sub(_amount);
		_balances[_staker] = _balances[_staker].sub(_amount);
		emit Withdrawn(_staker, _amount);
	}

	/**
	 * @notice Called when TCAP is burned or liquidated, transfers to the staker the current amount of rewards tokens earned.
   * @param _staker address
   * @dev Only vault can call it
   * @dev Updates rewards on call
   */
	function getRewardFromVault(address _staker)
	public
	onlyVault
	nonReentrant
	updateReward(_staker)
	{
		uint256 reward = rewards[_staker];
		if (reward > 0) {
			rewards[_staker] = 0;
			rewardsToken.safeTransfer(_staker, reward);
			emit RewardPaid(_staker, reward);
		}
	}

	/**
	 * @notice Transfers to the caller the current amount of rewards tokens earned.
   * @dev Updates rewards on call
   */
	function getReward() public nonReentrant updateReward(msg.sender) {
		uint256 reward = rewards[msg.sender];
		if (reward > 0) {
			rewards[msg.sender] = 0;
			rewardsToken.safeTransfer(msg.sender, reward);
			emit RewardPaid(msg.sender, reward);
		}
	}
}
