// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Inheritance
import { RewardsDistributionRecipient } from "./RewardsDistributionRecipient.sol";

contract StakingRewardsLP is
	RewardsDistributionRecipient,
	ReentrancyGuard,
	Ownable
{
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	/* ========== STATE VARIABLES ========== */

	IERC20 public rewardsToken;
	IERC20 public stakingToken;
	uint256 public periodFinish = 0;
	uint256 public rewardRate = 0;
	uint256 public rewardsDuration = 60 days;
	uint256 public lastUpdateTime;
	uint256 public rewardPerTokenStored;
	uint256 public lockPeriod = 7 days;
	uint256 public totalStakers = 0;

	mapping(address => uint256) public userRewardPerTokenPaid;
	mapping(address => uint256) public rewards;
	mapping(address => uint256) public lastStakedTime;

	uint256 private _totalSupply;
	mapping(address => uint256) private _balances;

	address private _positionManager;

	/* ========== CONSTRUCTOR ========== */

	constructor(
		address _rewardsDistribution,
		address _rewardsToken,
		address _stakingToken
	) {
		rewardsToken = IERC20(_rewardsToken);
		stakingToken = IERC20(_stakingToken);
		rewardsDistribution = _rewardsDistribution;
	}

	/* ========== VIEWS ========== */

	function totalSupply() external view returns (uint256) {
		return _totalSupply;
	}

	function balanceOf(address account) external view returns (uint256) {
		return _balances[account];
	}

	function lastTimeRewardApplicable() public view returns (uint256) {
		return Math.min(block.timestamp, periodFinish);
	}

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

	function earned(address account) public view returns (uint256) {
		return
			_balances[account]
				.mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
				.div(1e18)
				.add(rewards[account]);
	}

	function getRewardForDuration() external view returns (uint256) {
		return rewardRate.mul(rewardsDuration);
	}

	/* ========== MUTATIVE FUNCTIONS ========== */

	function stake(uint256 amount)
		external
		nonReentrant
		updateReward(msg.sender)
	{
		require(amount > 0, "Cannot stake 0");
		_totalSupply = _totalSupply.add(amount);
		if (_balances[msg.sender] == 0) totalStakers = totalStakers.add(1);
		_balances[msg.sender] = _balances[msg.sender].add(amount);
		stakingToken.safeTransferFrom(msg.sender, address(this), amount);
		lastStakedTime[msg.sender] = block.timestamp;
		emit Staked(msg.sender, amount);
	}

	function withdraw(uint256 amount)
		public
		nonReentrant
		updateReward(msg.sender)
	{
		require(amount > 0, "Cannot withdraw 0");
		require(
			lastStakedTime[msg.sender].add(lockPeriod) < block.timestamp,
			"Withdraw not possible in lock period"
		);
		_totalSupply = _totalSupply.sub(amount);
		_balances[msg.sender] = _balances[msg.sender].sub(amount);
		if (_balances[msg.sender] == 0) totalStakers = totalStakers.sub(1);
		stakingToken.safeTransfer(msg.sender, amount);
		emit Withdrawn(msg.sender, amount);
	}

	function withdrawByLoss(uint256 amount)
		public
		nonReentrant
		updateReward(msg.sender)
	{
		require(amount > 0, "Cannot withdraw 0");
		require(
			lastStakedTime[msg.sender].add(lockPeriod) > block.timestamp,
			"Withdraw not possible in lock period"
		);
		_totalSupply = _totalSupply.sub(amount);
		uint256 withdrawAmount = amount.mul(90).div(100);
		_balances[msg.sender] = _balances[msg.sender].sub(amount);
		if (_balances[msg.sender] == 0) totalStakers = totalStakers.sub(1);
		stakingToken.safeTransfer(msg.sender, withdrawAmount);
		bool success = stakingToken.transfer(
			address(0xdead),
			amount.sub(withdrawAmount)
		);

		require(success == true);
		emit Withdrawn(msg.sender, amount);
	}

	function getReward() public nonReentrant updateReward(msg.sender) {
		uint256 reward = rewards[msg.sender];
		if (reward > 0) {
			rewards[msg.sender] = 0;
			rewardsToken.safeTransfer(msg.sender, reward);
			emit RewardPaid(msg.sender, reward);
		}
	}

	function getRewardFor(address account) external nonReentrant onlyPositionManager updateReward(account) {
		uint256 reward = rewards[account];
		if (reward > 0) {
			rewards[account] = 0;
			rewardsToken.safeTransfer(account, reward);
			emit RewardPaid(account, reward);
		}
	}

	function exit() external {
		withdraw(_balances[msg.sender]);
		getReward();
	}

	function exitByLoss() external {
		withdrawByLoss(_balances[msg.sender]);
		getReward();
	}

	/* ========== RESTRICTED FUNCTIONS ========== */

	function notifyRewardAmount(uint256 reward)
		external
		override
		onlyRewardsDistribution
		updateReward(address(0))
	{
		if (block.timestamp >= periodFinish) {
			rewardRate = reward.div(rewardsDuration);
		} else {
			uint256 remaining = periodFinish.sub(block.timestamp);
			uint256 leftover = remaining.mul(rewardRate);
			rewardRate = reward.add(leftover).div(rewardsDuration);
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
		emit RewardAdded(reward);
	}

	function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
		require(periodFinish == 0 || block.timestamp > periodFinish, "period");
		rewardsDuration = _rewardsDuration;
		emit RewardsDurationUpdated(rewardsDuration);
	}

	function recoverERC20(address tokenAddress, uint256 tokenAmount)
		external
		onlyOwner
	{
		require(
			tokenAddress != address(stakingToken) &&
				tokenAddress != address(rewardsToken),
			"tokenAddress"
		);
		IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
		emit Recovered(tokenAddress, tokenAmount);
	}

	// PositionManager is set only here, doing it in constructor seems limiting
	function setPositionManager(address positionManager_) external onlyOwner {
		_positionManager = positionManager_;
		emit PositionManagerSet(_positionManager);
	}

	/* ========== MODIFIERS ========== */

	modifier updateReward(address account) {
		rewardPerTokenStored = rewardPerToken();
		lastUpdateTime = lastTimeRewardApplicable();
		if (account != address(0)) {
			rewards[account] = earned(account);
			userRewardPerTokenPaid[account] = rewardPerTokenStored;
		}
		_;
	}

	modifier onlyPositionManager() {
		require(msg.sender == _positionManager, "The function can be called only by the PositionManager");
		_;
	}

	/* ========== EVENTS ========== */

	event RewardAdded(uint256 reward);
	event Staked(address indexed user, uint256 amount);
	event Withdrawn(address indexed user, uint256 amount);
	event RewardPaid(address indexed user, uint256 reward);
	event RewardsDurationUpdated(uint256 newDuration);
	event Recovered(address token, uint256 amount);
	event PositionManagerSet(address positionManager);
}
