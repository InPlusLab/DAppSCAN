// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { GovStakingStorage } from "./GovStakingStorage.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { RewardsDistributionRecipient } from "./RewardsDistributionRecipient.sol";

interface ICommunityRewardsManager {
    function getStoreAddress() external view returns (address);
}

contract CommunityRewardsV2 is
    ReentrancyGuard,
    Ownable,
    RewardsDistributionRecipient
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    /* ========== STATE VARIABLES ========== */
    IERC20 public rewardsToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 1;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public earlyExitFee = 50; // in %
    uint256 public treasuryFeeShare = 0; // in %
    address public treasury;
    ICommunityRewardsManager public manager;
    mapping(address => bool) public allowed;
    mapping(address => uint256) public unclaimedAmounts;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public userRewardPerTokenPaid;
    struct v1User {
        address account;
        uint256 amount;
    }

    /* ========== CONSTRUCTOR ========== */
    constructor(
        address _rewardsToken,
        address _rewardsDistribution,
        address _stakingRewardsManager
    ) {
        rewardsToken = IERC20(_rewardsToken);
        rewardsDistribution = _rewardsDistribution;
        manager = ICommunityRewardsManager(_stakingRewardsManager);
    }

    /* ========== MODIFIER ========== */
    modifier onlyManager() {
        require(msg.sender == address(manager), "only allowed by manager");
        _;
    }
    modifier isAllowed() {
        require(allowed[msg.sender], "sender is not allowed to write");
        _;
    }

    /* ========== VIEWS ========== */
    function totalSupply() public view returns (uint256) {
        return
            GovStakingStorage(manager.getStoreAddress()).getRewardMultiplier();
    }

    function balanceOf(address account) external view returns (uint256) {
        return GovStakingStorage(manager.getStoreAddress()).getAmount(account);
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
        return _earned(account) + unclaimedAmounts[account];
    }

    function _earned(address account) internal view returns (uint256) {
        uint256 userMultiplier = GovStakingStorage(manager.getStoreAddress())
        .getUserMultiplier(account);
        return
            userMultiplier
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(getUserRewards(account));
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function getReward() external nonReentrant {
        require(
            block.timestamp >=
                GovStakingStorage(manager.getStoreAddress()).getLockDate(
                    msg.sender
                ),
            "unable to claim full reward"
        );
        updateReward(msg.sender);
        uint256 reward = getUserRewards(msg.sender);
        if (unclaimedAmounts[msg.sender] > 0) {
            reward += unclaimedAmounts[msg.sender];
            unclaimedAmounts[msg.sender] = 0;
        }
        if (reward > 0) {
            payReward(msg.sender, reward);
        }
    }

    function getRewardWithLoss() external nonReentrant {
        require(
            block.timestamp <
                GovStakingStorage(manager.getStoreAddress()).getLockDate(
                    msg.sender
                ),
            "user should claim full rewards"
        );
        updateReward(msg.sender);
        uint256 reward = getUserRewards(msg.sender);
        if (unclaimedAmounts[msg.sender] > 0) {
            reward += unclaimedAmounts[msg.sender];
            unclaimedAmounts[msg.sender] = 0;
        }
        if (reward > 0) {
            uint256 fee = (reward * earlyExitFee) / 100;
            uint256 feeToTreasury = (fee * treasuryFeeShare) / 100;
            if (feeToTreasury > 0) {
                rewardsToken.safeTransfer(treasury, feeToTreasury);
            }
            payReward(msg.sender, reward - fee);
            _notifyRewardAmount(fee - feeToTreasury);
        }
    }

    function payReward(address user, uint256 reward) internal {
        setUserRewards(user, 0);
        rewardsToken.safeTransfer(user, reward);
        emit RewardPaid(user, reward);
    }

    function updateReward(address account) public {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            setUserRewards(account, _earned(account));
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
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
            block.timestamp >=
                GovStakingStorage(manager.getStoreAddress()).getLockDate(
                    msg.sender
                ),
            "unable to claim full reward"
        );
        updateReward(user);
        uint256 reward = getUserRewards(user);
        if (unclaimedAmounts[user] > 0) {
            reward += unclaimedAmounts[user];
            unclaimedAmounts[user] = 0;
        }
        if (reward > 0) {
            payReward(user, reward);
        }
    }

    function rewardPerTokenSnapshot(uint256 totalRewardMultiplierSnapshot)
        internal
        view
        returns (uint256)
    {
        if (totalRewardMultiplierSnapshot == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalRewardMultiplierSnapshot)
            );
    }

    function resetInactiveMultipliers(
        uint256 totalRewardMultiplierSnapshot,
        address[] memory users
    ) external onlyManager {
        uint256 _rewardPerTokenSnapshot = rewardPerTokenSnapshot(
            totalRewardMultiplierSnapshot
        );
        GovStakingStorage store = GovStakingStorage(manager.getStoreAddress());
        for (uint256 i = 0; i < users.length; i++) {
            GovStakingStorage.UserInfo memory user = GovStakingStorage(
                manager.getStoreAddress()
            ).getUserInformation(users[i]);
            if (
                user.rewardMultiplier != 0 &&
                user.lockStart + user.lockPeriod < block.timestamp
            ) {
                // during resetting rewardPerToken value changes along with the totalSupply()
                // we need to save unclaimedAmounts based on the values before resetting process started
                // thus, _earned() function logics are used here, but with the snapshot value of rewardPerToken
                unclaimedAmounts[users[i]] += user
                .rewardMultiplier
                .mul(
                    _rewardPerTokenSnapshot.sub(
                        userRewardPerTokenPaid[users[i]]
                    )
                ).div(1e18)
                .add(getUserRewards(users[i]));
                setUserRewards(users[i], 0);
                store.removeRewardMultiplier(users[i]);
                emit MultiplierReset(users[i]);
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
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
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
        emit ExitFeeChanged(fee);
    }

    function setTreasuryFeeShare(uint256 share) external onlyOwner {
        require(treasury != address(0), "treasury address is not set");
        require(share <= 100 && share > 0, "invalid share");
        treasuryFeeShare = share;
        emit TreasuryFeeChanged(share);
    }

    function setCommunityManager(address newManager) external onlyOwner {
        manager = ICommunityRewardsManager(newManager);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
    }

    function setWriteAllowance(address to, bool flag) external onlyOwner {
        allowed[to] = flag;
    }

    function setPreviouslyUnclaimed(v1User[] memory users) external isAllowed {
        for (uint256 i = 0; i < users.length; i++) {
            unclaimedAmounts[users[i].account] = users[i].amount;
        }
    }

    function setPreviouslyUnclaimedForSingleUser(address user, uint256 amount)
        external
        isAllowed
    {
        unclaimedAmounts[user] = amount;
    }

    /* ========== EVENTS ========== */
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event MultiplierReset(address indexed user);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event ExitFeeChanged(uint256 newFee);
    event TreasuryFeeChanged(uint256 newFee);
}
