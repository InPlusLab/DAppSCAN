// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;
/**
 *Submitted for verification at Etherscan.io on 2020-07-17
 */

/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/
* Synthetix: STNDRewards.sol
*
* Docs: https://docs.synthetix.io/
*
*
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

// File: @openzeppelin/contracts/utils/math/Math.sol

import "@openzeppelin/contracts/utils/math/Math.sol";

// File: @openzeppelin/contracts/utils/math/SafeMath.sol

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// File: @openzeppelin/contracts/utils/Address.sol

import "@openzeppelin/contracts/utils/Address.sol";

// File: @openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// File: contracts/pools/IRewardDistributionRecipient.sol

import "./IRewardDistributionRecipient.sol";

// File: contracts/pools/LPTokenWrapper.sol

import "./LPTokenWrapper.sol";

contract WETHSTNDLPTokenSharePool is
    LPTokenWrapper,
    IRewardDistributionRecipient
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IERC20 public stnd;
    address private operator;
    uint256 public constant DURATION = 60 days;

    uint256 public initreward = 300000 * 10**18;
    uint256 public starttime; // starttime TBD
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(
        address stnd_,
        address lptoken_,
        uint256 starttime_
    ) {
        stnd = IERC20(stnd_);
        lpt = IERC20(lptoken_);
        starttime = starttime_;
        operator = msg.sender;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalInput() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalInput())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount)
        public
        override
        updateReward(msg.sender)
        checkStart
    {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        override
        updateReward(msg.sender)
        checkStart
    {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) checkStart {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            stnd.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function emergencyWithdraw(uint256 amount) public {
        require(msg.sender == operator, "Not the operator of the pool");
        stnd.safeTransfer(msg.sender, amount);
    }

    modifier checkStart() {
        require(block.timestamp >= starttime, "not start");
        _;
    }

    function notifyRewardAmount(uint256 reward)
        external
        override
        onlyOwner
        updateReward(address(0))
    {
        if (block.timestamp > starttime) {
            if (block.timestamp >= periodFinish) {
                rewardRate = reward.div(DURATION);
            } else {
                uint256 remaining = periodFinish.sub(block.timestamp);
                uint256 leftover = remaining.mul(rewardRate);
                rewardRate = reward.add(leftover).div(DURATION);
            }
            lastUpdateTime = block.timestamp;
            periodFinish = block.timestamp.add(DURATION);
            emit RewardAdded(reward);
        } else {
            rewardRate = initreward.div(DURATION);
            lastUpdateTime = starttime;
            periodFinish = starttime.add(DURATION);
            require(rewardRate <= balanceOf(address(this)).div(DURATION));
            emit RewardAdded(initreward);
        }
    }
}
