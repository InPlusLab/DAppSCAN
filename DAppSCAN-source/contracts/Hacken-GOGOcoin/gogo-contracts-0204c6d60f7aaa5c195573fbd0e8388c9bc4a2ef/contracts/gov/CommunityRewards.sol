// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { GovStakingStorage } from "./GovStakingStorage.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import { RewardsDistributionRecipient } from "../staking/RewardsDistributionRecipient.sol";

contract CommunityRewards is
    ReentrancyGuard,
    Ownable,
    RewardsDistributionRecipient
{
    using SafeMath for uint256;
    /* ========== STATE VARIABLES ========== */

    GovStakingStorage store;
    IERC20 public rewardsToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 1;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public earlyExitFee = 50; // in %
    address public manager;

    mapping(address => uint256) public unclaimedAmounts;
    mapping(address => uint256) public rewards;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _rewardsToken,
        address _storageAddress,
        address _rewardsDistribution,
        address _stakingRewardsManager
    ) {
        store = GovStakingStorage(_storageAddress);
        rewardsToken = IERC20(_rewardsToken);
        rewardsDistribution = _rewardsDistribution;
        manager = _stakingRewardsManager;
    }

    /* ========== MODIFIER ========== */

    modifier onlyManager() {
        require(msg.sender == manager, "only allowed by manager");
        _;
    }

    /* ========== VIEWS ========== */

    function totalSupply() public view returns (uint256) {
        return store.getRewardMultiplier();
    }

    function balanceOf(address account) external view returns (uint256) {
        return store.getAmount(account);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        uint256 userMultiplier = store.getUserMultiplier(account);

        return
            userMultiplier == 0
                ? unclaimedAmounts[account]
                : userMultiplier
                    .mul(
                    rewardPerToken().sub(
                        store.getUserRewardPerTokenPaid(account)
                    )
                ).div(1e18)
                    .add(getUserRewards(account));
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function getReward() public nonReentrant {
        require(
            block.timestamp >= store.getLockDate(msg.sender),
            "unable to claim full reward"
        );
        updateReward(msg.sender);
        uint256 reward = getUserRewards(msg.sender);
        if (reward > 0) {
            payReward(msg.sender, reward);
        }
    }

    function getRewardWithLoss() public nonReentrant {
        require(
            block.timestamp < store.getLockDate(msg.sender),
            "user should claim full rewards"
        );
        updateReward(msg.sender);
        uint256 reward = getUserRewards(msg.sender);
        if (reward > 0) {
            uint256 fee = (reward * earlyExitFee) / 100;
            payReward(msg.sender, reward - fee);
            _notifyRewardAmount(fee);
        }
    }

    function payReward(address user, uint256 reward) internal {
        setUserRewards(user, 0);
        rewardsToken.transfer(user, reward);
        emit RewardPaid(user, reward);
    }

    function updateReward(address account) public {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            setUserRewards(account, earned(account));
            store.setUserRewardPerTokenPaid(account, rewardPerTokenStored);
        }
    }

    function setUserRewards(address user, uint256 amount) internal {
        rewards[user] = amount;
    }

    function getUserRewards(address user) public view returns (uint256) {
        return rewards[user];
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function getRewardFor(address user) external onlyManager {
        require(
            block.timestamp >= store.getLockDate(msg.sender),
            "unable to claim full reward"
        );
        updateReward(user);
        uint256 reward = getUserRewards(user);
        if (reward > 0) {
            payReward(user, reward);
        }
    }

    function resetInactiveMultipliers(address[] memory users)
        external
        onlyManager
    {
        for (uint256 i = 0; i < users.length; i++) {
            GovStakingStorage.UserInfo memory user = store.getUserInformation(
                users[i]
            );
            if (user.lockStart + user.lockPeriod < block.timestamp) {
                unclaimedAmounts[users[i]] += earned(users[i]);
                store.removeRewardMultiplier(users[i]);
            }
        }
    }

    function notifyRewardAmount(uint256 reward)
        external
        override
        onlyRewardsDistribution
    {
        _notifyRewardAmount(reward);
    }

    function _notifyRewardAmount(uint256 reward) internal {
        updateReward(address(0));
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

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        IERC20(tokenAddress).transfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setRewardsDistributionAddress(address newDistributer)
        external
        onlyOwner
    {
        rewardsDistribution = newDistributer;
    }

    function setEarlyExitFee(uint256 fee) external onlyOwner {
        require(fee <= 100 && fee > 0, "invalid fee");
        earlyExitFee = fee;
    }

    function setStorage(address newStorage) external onlyOwner {
        store = GovStakingStorage(newStorage);
    }

    function setCommunityManager(address newManager) external onlyOwner {
        manager = newManager;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
}
