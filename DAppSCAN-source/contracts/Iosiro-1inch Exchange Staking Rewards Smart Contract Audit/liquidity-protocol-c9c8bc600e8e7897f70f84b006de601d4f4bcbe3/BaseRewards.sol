// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./BalanceAccounting.sol";


contract BaseRewards is Ownable, BalanceAccounting {
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);

    struct TokenRewards {
        IERC20 gift;
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
            tr.rewardPerTokenStored = rewardPerToken(i);
            tr.lastUpdateTime = lastTimeRewardApplicable(i);
            if (account != address(0)) {
                tr.rewards[account] = earned(i, account);
                tr.userRewardPerTokenPaid[account] = tr.rewardPerTokenStored;
            }
        }
        _;
    }

    modifier onlyRewardDistribution(uint i) {
        require(msg.sender == tokenRewards[i].rewardDistribution, "Access denied");
        _;
    }

    function lastTimeRewardApplicable(uint i) public view returns (uint256) {
        return Math.min(block.timestamp, tokenRewards[i].periodFinish);
    }

    function rewardPerToken(uint i) public view returns (uint256) {
        TokenRewards storage tr = tokenRewards[i];
        if (totalSupply() == 0) {
            return tr.rewardPerTokenStored;
        }
        return tr.rewardPerTokenStored.add(
            lastTimeRewardApplicable(i)
                .sub(tr.lastUpdateTime)
                .mul(tr.rewardRate)
                .mul(1e18)
                .div(totalSupply())
        );
    }

    function earned(uint i, address account) public view returns (uint256) {
        TokenRewards storage tr = tokenRewards[i];
        return balanceOf(account)
            .mul(rewardPerToken(i).sub(tr.userRewardPerTokenPaid[account]))
            .div(1e18)
            .add(tr.rewards[account]);
    }
//SWC-107-Reentrancy: L75
    function getReward(uint i) public updateReward(msg.sender) {
        TokenRewards storage tr = tokenRewards[i];
        uint256 reward = tr.rewards[msg.sender];
        if (reward > 0) {
            tr.rewards[msg.sender] = 0;
            tr.gift.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function notifyRewardAmount(uint i, uint256 reward) external onlyRewardDistribution(i) updateReward(address(0)) {
        TokenRewards storage tr = tokenRewards[i];
        uint256 duration = tr.duration;

        if (block.timestamp >= tr.periodFinish) {
            tr.rewardRate = reward.div(duration);
        } else {
            uint256 remaining = tr.periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(tr.rewardRate);
            tr.rewardRate = reward.add(leftover).div(duration);
        }

        uint balance = tr.gift.balanceOf(address(this));
        require(tr.rewardRate <= balance.div(duration), "Reward is too big");
//SWC-101-Integer Overflow and Underflow: L98
        tr.lastUpdateTime = block.timestamp;
        tr.periodFinish = block.timestamp.add(duration);
        emit RewardAdded(reward);
    }

    function setRewardDistribution(uint i, address _rewardDistribution) external onlyOwner {
        TokenRewards storage tr = tokenRewards[i];
        tr.rewardDistribution = _rewardDistribution;
    }

    function setDuration(uint i, uint256 _duration) external onlyRewardDistribution(i) {
        TokenRewards storage tr = tokenRewards[i];
        require(block.timestamp >= tr.periodFinish, "Access denied");
        tr.duration = _duration;
    }

    function addGift(IERC20 gift, uint256 duration, address rewardDistribution) public onlyOwner {
        TokenRewards storage tr = tokenRewards.push();
        tr.gift = gift;
        tr.duration = duration;
        tr.rewardDistribution = rewardDistribution;
        // TODO: test gas usage
        // tokenRewards.push(TokenRewards({
        //     gift: gift,
        //     duration: duration,
        //     rewardDistribution: rewardDistribution,
        //     periodFinish: 0,
        //     rewardRate: 0,
        //     lastUpdateTime: 0,
        //     rewardPerTokenStored: 0
        // }));
    }
}
