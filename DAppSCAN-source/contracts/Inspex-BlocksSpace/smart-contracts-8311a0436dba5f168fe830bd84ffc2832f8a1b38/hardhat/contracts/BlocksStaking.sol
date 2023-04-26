pragma solidity 0.8.5;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BLSToken.sol";

/**
 * @dev This contract implements the logic for staking BLS amount. It
 * also handles BNB rewards distribution to users for their blocks taken
 * over (that got covered) and rewards for staked BLS amount.
 */
contract BlocksStaking is Ownable {
    using SafeERC20 for BLSToken;

    // Object with information for a user
    struct UserInfo {
        uint256 amount; // Amount of amount being staked
        uint256 rewardDebt;
        uint256 takeoverReward; // Reward for covered blocks
    }

    uint256 constant BURN_PERCENT_WITHDRAWAL = 1; // Withdrawals burning 1% of your tokens. Deflationary, adding value
    uint256 public rewardsDistributionPeriod = 24 days / 3; // How long are we distributing incoming rewards
    // Global staking variables
    uint256 public totalTokens; // Total amount of amount currently staked
    uint256 public rewardsPerBlock; // Multiplied by 1e12 for better division precision
    uint256 public rewardsFinishedBlock; // When will rewards distribution end
    uint256 public accRewardsPerShare; // Accumulated rewards per share
    uint256 public lastRewardCalculatedBlock; // Last time we calculated accumulation of rewards per share
    uint256 public allUsersRewardDebt; // Helper to keep track of proper account balance for distribution
    uint256 public takeoverRewards; // Helper to keep track of proper account balance for distribution

    // Mapping of UserInfo object to a wallet
    mapping(address => UserInfo) public userInfo;

    // The BLS token contract
    BLSToken private blsToken;

    // Event that is triggered when a user claims his rewards
    event Claim(address indexed user, uint256 reward);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event RewardDistributionPeriodSet(uint256 period);

    /**
     * @dev Provides addresses for BLS token contract
     */
    constructor(BLSToken blsTokenAddress_) {
        blsToken = BLSToken(blsTokenAddress_);
    }

    function setRewardDistributionPeriod(uint256 period_) external onlyOwner {
        rewardsDistributionPeriod = period_;
        emit RewardDistributionPeriodSet(period_);
    }

    // View function to see pending BLSs on frontend.
    function pendingRewards(address user_) public view returns (uint256) {
        UserInfo storage user = userInfo[user_];
        uint256 tempAccRewardsPerShare = accRewardsPerShare;
        if (user.amount > 0) {
            tempAccRewardsPerShare = tempAccRewardsPerShare + (rewardsPerBlock * getMultiplier()) / totalTokens;
        }
        return ((tempAccRewardsPerShare * user.amount) / 1e12) + user.takeoverReward - user.rewardDebt;
    }

    // View function for showing rewards counter on frontend. Its multiplied by 1e12
    function rewardsPerBlockPerToken() external view returns(uint256) {
        if (block.number > rewardsFinishedBlock || totalTokens <= 0) {
            return 0;
        } else {
            return rewardsPerBlock / totalTokens;
        }
    }

    function getMultiplier() internal view returns (uint256) {
        if (block.number > rewardsFinishedBlock) {
            if(rewardsFinishedBlock >= lastRewardCalculatedBlock){
                return rewardsFinishedBlock - lastRewardCalculatedBlock;
            }else{
                return 0;
            }
        }else{
            return block.number - lastRewardCalculatedBlock;
        }
    }

    function updateState() internal {
        if(totalTokens > 0){
            accRewardsPerShare = accRewardsPerShare + (rewardsPerBlock * getMultiplier()) / totalTokens;
        }
        lastRewardCalculatedBlock = block.number;
    }

    /**
     * @dev The user deposits BLS amount for staking.
     */
    function deposit(uint256 amount_) external {
        UserInfo storage user = userInfo[msg.sender];
        // if there are staked amount, fully harvest current reward
        if (user.amount > 0) {
            claim();
        }

        if (totalTokens > 0) {
            updateState();
        } else {
            calculateRewardsDistribution(); // Means first time any user deposits, so start distributing
            lastRewardCalculatedBlock = block.number;
        }    

        totalTokens = totalTokens + amount_; // sum of total staked amount
        uint256 userRewardDebtBefore = user.rewardDebt;
        user.amount = user.amount + amount_; // cache staked amount count for this wallet
        user.rewardDebt = (accRewardsPerShare * user.amount) / 1e12; // cache current total reward per token
        allUsersRewardDebt = allUsersRewardDebt + user.rewardDebt - userRewardDebtBefore;
        emit Deposit(msg.sender, amount_);
        // Transfer BLS amount from the user to this contract
        blsToken.safeTransferFrom(address(msg.sender), address(this), amount_);
    }

    /**
     * @dev The user withdraws staked BLS amount and claims the rewards.
     */
    function withdraw() external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        require(amount > 0, "No amount deposited for withdrawal.");
        // Claim any available rewards
        claim();

        totalTokens = totalTokens - amount;
        // If after withdraw, there is noone else staking and there are still rewards to be distributed, then reset rewards debt
        if(totalTokens == 0 && rewardsFinishedBlock > block.number){
            allUsersRewardDebt = 0;
        }else{
            // Deduct whatever was added when it was claimed
            allUsersRewardDebt = allUsersRewardDebt - user.rewardDebt;
        }
        user.amount = 0;
        user.rewardDebt = 0;

        uint256 burnAmount = amount * BURN_PERCENT_WITHDRAWAL / 100;
        blsToken.burn(burnAmount);

        // Transfer BLS amount from this contract to the user
        uint256 amountWithdrawn = safeBlsTransfer(address(msg.sender), amount - burnAmount);
        emit Withdraw(msg.sender, amountWithdrawn);
    }
    
    /**
     * @dev The user just withdraws staked BLS amount and leaves any rewards.
     */
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];

        uint256 amount = user.amount;
        totalTokens = totalTokens - amount;
        allUsersRewardDebt = allUsersRewardDebt - user.rewardDebt;
        user.amount = 0;
        user.rewardDebt = 0;
        user.takeoverReward = 0;

        uint256 burnAmount = amount * BURN_PERCENT_WITHDRAWAL / 100;
        blsToken.burn(burnAmount);

        // Transfer BLS amount from this contract to the user
        uint256 amountWithdrawn = safeBlsTransfer(address(msg.sender), amount - burnAmount);
        emit EmergencyWithdraw(msg.sender, amountWithdrawn);
    }

    /**
     * @dev Claim rewards from staking and covered blocks.
     */
    function claim() public {
        // Update contract state
        updateState();

        uint256 reward = pendingRewards(msg.sender);
        if (reward <= 0) return; // skip if no rewards

        UserInfo storage user = userInfo[msg.sender];
        takeoverRewards = takeoverRewards - user.takeoverReward;
        user.rewardDebt = (accRewardsPerShare * user.amount) / 1e12; // reset: cache current total reward per token
        allUsersRewardDebt = allUsersRewardDebt + reward - user.takeoverReward;
        user.takeoverReward = 0; // reset takeover reward

        // transfer reward in BNBs to the user
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Transfer failed.");
        emit Claim(msg.sender, reward);
    }

    /**
     * @dev Distribute rewards for covered blocks, what remains goes for staked amount.
     */
    function distributeRewards(address[] calldata addresses_, uint256[] calldata rewards_) external payable {
        uint256 tmpTakeoverRewards;
        for (uint256 i = 0; i < addresses_.length; ++i) {
            // process each reward for covered blocks
            userInfo[addresses_[i]].takeoverReward = userInfo[addresses_[i]].takeoverReward + rewards_[i]; // each user that got blocks covered gets a reward
            tmpTakeoverRewards = tmpTakeoverRewards + rewards_[i];
        }
        takeoverRewards = takeoverRewards + tmpTakeoverRewards;

        // what remains is the reward for staked amount
        if (msg.value - tmpTakeoverRewards > 0 && totalTokens > 0) {
            // Update rewards per share because balance changes
            updateState();
            calculateRewardsDistribution();
        }
    }

    function calculateRewardsDistribution() internal {
        uint256 allReservedRewards = (accRewardsPerShare * totalTokens) / 1e12;
        uint256 availableForDistribution = (address(this).balance + allUsersRewardDebt - allReservedRewards - takeoverRewards);
        rewardsPerBlock = (availableForDistribution * 1e12) / rewardsDistributionPeriod;
        rewardsFinishedBlock = block.number + rewardsDistributionPeriod;
    }

    /**
     * @dev Safe BLS transfer function in case of a rounding error. If not enough amount in the contract, trensfer all of them.
     */
    function safeBlsTransfer(address to_, uint256 amount_) internal returns (uint256) {
        uint256 blsBalance = blsToken.balanceOf(address(this));
        if (amount_ > blsBalance) {
            blsToken.transfer(to_, blsBalance);
            return blsBalance;
        } else {
            blsToken.transfer(to_, amount_);
            return amount_;
        }
    }
}
