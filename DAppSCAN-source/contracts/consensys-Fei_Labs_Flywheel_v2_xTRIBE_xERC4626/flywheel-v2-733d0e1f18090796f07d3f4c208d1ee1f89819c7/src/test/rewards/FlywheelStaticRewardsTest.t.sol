// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FlywheelCore} from "../../FlywheelCore.sol";

import {FlywheelStaticRewards, Authority} from "../../rewards/FlywheelStaticRewards.sol";

contract FlywheelStaticRewardsTest is DSTestPlus {
    FlywheelStaticRewards rewards;

    MockERC20 strategy;
    MockERC20 public rewardToken;

    function setUp() public {
        rewardToken = new MockERC20("test token", "TKN", 18);

        strategy = new MockERC20("test strategy", "TKN", 18);

        rewards = new FlywheelStaticRewards(FlywheelCore(address(this)), address(this), Authority(address(0)));
    }

    function testSetRewardsInfo() public {
        (uint224 rewardsPerSecond, uint32 rewardsEndTimestamp) = rewards.rewardsInfo(strategy);
        require(rewardsPerSecond == 0);
        require(rewardsEndTimestamp == 0);

        uint32 newEnd = uint32(block.timestamp) + 100;
        rewards.setRewardsInfo(
            strategy,
            FlywheelStaticRewards.RewardsInfo({rewardsPerSecond: 1 ether, rewardsEndTimestamp: newEnd})
        );

        (rewardsPerSecond, rewardsEndTimestamp) = rewards.rewardsInfo(strategy);

        require(rewardsPerSecond == 1 ether);
        require(rewardsEndTimestamp == newEnd);
    }

    function testGetAccruedRewards() public {
        hevm.warp(1000);
        testSetRewardsInfo();

        rewardToken.mint(address(rewards), 100 ether);

        require(rewards.getAccruedRewards(strategy, uint32(block.timestamp - 10)) == 10 ether);
        require(rewardToken.balanceOf(address(rewards)) == 100 ether);
    }

    function testGetAccruedRewardsAfterEnd() public {
        hevm.warp(1000);
        testSetRewardsInfo();
        hevm.warp(2000);

        rewardToken.mint(address(rewards), 100 ether);

        require(rewards.getAccruedRewards(strategy, uint32(block.timestamp - 1000)) == 100 ether);
        require(rewardToken.balanceOf(address(rewards)) == 100 ether);
    }

    function testGetAccruedRewardsCappedAfterEnd() public {
        hevm.warp(1000);
        testSetRewardsInfo();
        hevm.warp(2000);

        rewardToken.mint(address(rewards), 20 ether);

        require(rewards.getAccruedRewards(strategy, uint32(block.timestamp - 1000)) == 100 ether);
        require(rewardToken.balanceOf(address(rewards)) == 20 ether);
    }
}
