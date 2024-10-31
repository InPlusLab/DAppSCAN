// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./BalanceAccounting.sol";

/// @title Base contract for reward mechanics
abstract contract BaseRewards is Ownable, BalanceAccounting {
    using SafeERC20 for IERC20;

    event RewardAdded(uint256 indexed i, uint256 reward);
    event RewardPaid(uint256 indexed i, address indexed user, uint256 reward);
    event DurationUpdated(uint256 indexed i, uint256 duration);
    event ScaleUpdated(uint256 indexed i, uint256 scale);
    event RewardDistributionChanged(uint256 indexed i, address rewardDistribution);
    event NewGift(uint256 indexed i, IERC20 gift);

    struct TokenRewards {
        IERC20 gift;
        uint256 scale;
        uint256 duration;
        address rewardDistribution;

        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;
    }

    TokenRewards[] public tokenRewards;

    modifier updateReward(address account) {
        uint256 len = tokenRewards.length;
        for (uint i = 0; i < len; i++) {
            TokenRewards storage tr = tokenRewards[i];
            uint256 newRewardPerToken = rewardPerToken(i);
            tr.rewardPerTokenStored = newRewardPerToken;
            tr.lastUpdateTime = lastTimeRewardApplicable(i);
            if (account != address(0)) {
                tr.rewards[account] = _earned(i, account, newRewardPerToken);
                tr.userRewardPerTokenPaid[account] = newRewardPerToken;
            }
        }
        _;
    }

    modifier onlyRewardDistribution(uint i) {
        require(msg.sender == tokenRewards[i].rewardDistribution, "Access denied");
        _;
    }

    /// @notice Returns last time specific token reward was applicable
    function lastTimeRewardApplicable(uint i) public view returns (uint256) {
        return Math.min(block.timestamp, tokenRewards[i].periodFinish);
    }

    /// @notice Returns current reward per token
    function rewardPerToken(uint i) public view returns (uint256) {
        TokenRewards storage tr = tokenRewards[i];
        if (totalSupply() == 0) {
            return tr.rewardPerTokenStored;
        }
        return tr.rewardPerTokenStored.add(
            lastTimeRewardApplicable(i)
                .sub(tr.lastUpdateTime)
                .mul(tr.rewardRate)
                .div(totalSupply())
        );
    }

    /// @notice Returns how many tokens account currently has
    function earned(uint i, address account) public view returns (uint256) {
        return _earned(i, account, rewardPerToken(i));
    }

    /// @notice Withdraws `msg.sender`'s reward
    function getReward(uint i) public updateReward(msg.sender) {
        TokenRewards storage tr = tokenRewards[i];
        uint256 reward = tr.rewards[msg.sender];
        if (reward > 0) {
            tr.rewards[msg.sender] = 0;
            tr.gift.safeTransfer(msg.sender, reward);
            emit RewardPaid(i, msg.sender, reward);
        }
    }

    /// @notice Same as `getReward` but for all listed tokens
    function getAllRewards() public {
        uint256 len = tokenRewards.length;
        for (uint i = 0; i < len; i++) {
            getReward(i);
        }
    }

    /// @notice Updates specific token rewards amount
    function notifyRewardAmount(uint i, uint256 reward) external onlyRewardDistribution(i) updateReward(address(0)) {
        TokenRewards storage tr = tokenRewards[i];
        uint256 scale = tr.scale;
        require(reward < uint(-1).div(scale), "Reward overlow");
        uint256 duration = tr.duration;
        uint256 rewardRate;

        if (block.timestamp >= tr.periodFinish) {
            require(reward >= duration, "Reward is too small");
            rewardRate = reward.mul(scale).div(duration);
        } else {
            uint256 remaining = tr.periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(tr.rewardRate).div(scale);
            require(reward.add(leftover) >= duration, "Reward is too small");
            rewardRate = reward.add(leftover).mul(scale).div(duration);
        }

        uint balance = tr.gift.balanceOf(address(this));
        require(rewardRate <= balance.mul(scale).div(duration), "Reward is too big");

        tr.rewardRate = rewardRate;
        tr.lastUpdateTime = block.timestamp;
        tr.periodFinish = block.timestamp.add(duration);
        emit RewardAdded(i, reward);
    }

    /// @notice Updates rewards distributor
    function setRewardDistribution(uint i, address _rewardDistribution) external onlyOwner {
        TokenRewards storage tr = tokenRewards[i];
        tr.rewardDistribution = _rewardDistribution;
        emit RewardDistributionChanged(i, _rewardDistribution);
    }

    /// @notice Updates rewards duration
    function setDuration(uint i, uint256 duration) external onlyRewardDistribution(i) {
        TokenRewards storage tr = tokenRewards[i];
        require(block.timestamp >= tr.periodFinish, "Not finished yet");
        tr.duration = duration;
        emit DurationUpdated(i, duration);
    }

    /// @notice Updates rewards scale
    function setScale(uint i, uint256 scale) external onlyOwner {
        require(scale > 0, "Scale is too low");
        require(scale <= 1e36, "Scale si too high");
        TokenRewards storage tr = tokenRewards[i];
        require(tr.periodFinish == 0, "Can't change scale after start");
        tr.scale = scale;
        emit ScaleUpdated(i, scale);
    }

    /// @notice Adds new token to the list
    function addGift(IERC20 gift, uint256 duration, address rewardDistribution, uint256 scale) public onlyOwner {
        require(scale > 0, "Scale is too low");
        require(scale <= 1e36, "Scale is too high");
        uint256 len = tokenRewards.length;
        for (uint i = 0; i < len; i++) {
            require(gift != tokenRewards[i].gift, "Gift is already added");
        }

        TokenRewards storage tr = tokenRewards.push();
        tr.gift = gift;
        tr.duration = duration;
        tr.rewardDistribution = rewardDistribution;
        tr.scale = scale;

        emit NewGift(len, gift);
        emit DurationUpdated(len, duration);
        emit RewardDistributionChanged(len, rewardDistribution);
    }

    function _earned(uint i, address account, uint256 _rewardPerToken) private view returns (uint256) {
        TokenRewards storage tr = tokenRewards[i];
        return balanceOf(account)
            .mul(_rewardPerToken.sub(tr.userRewardPerTokenPaid[account]))
            .div(tr.scale)
            .add(tr.rewards[account]);
    }
}
