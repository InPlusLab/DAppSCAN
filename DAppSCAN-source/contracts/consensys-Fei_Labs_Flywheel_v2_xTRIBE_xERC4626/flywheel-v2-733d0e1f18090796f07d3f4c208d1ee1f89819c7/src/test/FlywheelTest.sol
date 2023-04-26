// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockBooster} from "./mocks/MockBooster.sol";
import {MockRewards} from "./mocks/MockRewards.sol";

import "../FlywheelCore.sol";

contract FlywheelTest is DSTestPlus {
    FlywheelCore flywheel;
    MockRewards rewards;
    MockBooster booster;

    MockERC20 strategy;
    MockERC20 rewardToken;

    address constant user = address(0xDEAD);
    address constant user2 = address(0xBEEF);

    function setUp() public {
        rewardToken = new MockERC20("test token", "TKN", 18);

        strategy = new MockERC20("test strategy", "TKN", 18);

        booster = new MockBooster();

        flywheel = new FlywheelCore(
            rewardToken,
            MockRewards(address(0)),
            IFlywheelBooster(address(0)),
            address(this),
            Authority(address(0))
        );

        rewards = new MockRewards(flywheel);

        flywheel.setFlywheelRewards(rewards);
    }

    function testAddStrategy(ERC20 strat) public {
        flywheel.addStrategyForRewards(strat);
        (uint224 index, uint32 timestamp) = flywheel.strategyState(strat);
        require(index == flywheel.ONE());
        require(timestamp == block.timestamp);
    }

    function testFailAddStrategy() public {
        hevm.prank(address(1));
        flywheel.addStrategyForRewards(strategy);
    }

    function testSetFlywheelRewards(uint256 mintAmount) public {
        rewardToken.mint(address(rewards), mintAmount);

        flywheel.setFlywheelRewards(IFlywheelRewards(address(1)));
        require(flywheel.flywheelRewards() == IFlywheelRewards(address(1)));

        // assert rewards transferred
        require(rewardToken.balanceOf(address(1)) == mintAmount);
        require(rewardToken.balanceOf(address(rewards)) == 0);
    }

    function testSetFlywheelRewardsUnauthorized() public {
        hevm.prank(address(1));
        hevm.expectRevert(bytes("UNAUTHORIZED"));
        flywheel.setFlywheelRewards(IFlywheelRewards(address(1)));
    }

    function testSetFlywheelBooster(IFlywheelBooster booster) public {
        flywheel.setBooster(booster);
        require(flywheel.flywheelBooster() == booster);
    }

    function testSetFlywheelBoosterUnauthorized() public {
        hevm.prank(address(1));
        hevm.expectRevert(bytes("UNAUTHORIZED"));
        flywheel.setBooster(IFlywheelBooster(address(1)));
    }

    function testAccrue(
        uint128 userBalance1,
        uint128 userBalance2,
        uint128 rewardAmount
    ) public {
        hevm.assume(userBalance1 != 0 && userBalance2 != 0 && rewardAmount != 0);
        strategy.mint(user, userBalance1);
        strategy.mint(user2, userBalance2);

        rewardToken.mint(address(rewards), rewardAmount);
        rewards.setRewardsAmount(strategy, rewardAmount);

        flywheel.addStrategyForRewards(strategy);

        uint256 accrued = flywheel.accrue(strategy, user);

        (uint224 index, ) = flywheel.strategyState(strategy);

        uint256 diff = (rewardAmount * flywheel.ONE()) / (uint256(userBalance1) + userBalance2);

        require(index == flywheel.ONE() + diff);
        require(flywheel.userIndex(strategy, user) == index);
        require(flywheel.rewardsAccrued(user) == (diff * userBalance1) / flywheel.ONE());
        require(accrued == (diff * userBalance1) / flywheel.ONE());
        require(flywheel.rewardsAccrued(user2) == 0 ether);

        require(rewardToken.balanceOf(address(rewards)) == rewardAmount);
    }

    function testAccrueTwoUsers(
        uint128 userBalance1,
        uint128 userBalance2,
        uint128 rewardAmount
    ) public {
        hevm.assume(userBalance1 != 0 && userBalance2 != 0 && rewardAmount != 0);

        strategy.mint(user, userBalance1);
        strategy.mint(user2, userBalance2);

        rewardToken.mint(address(rewards), rewardAmount);
        rewards.setRewardsAmount(strategy, rewardAmount);

        flywheel.addStrategyForRewards(strategy);

        (uint256 accrued1, uint256 accrued2) = flywheel.accrue(strategy, user, user2);

        (uint224 index, ) = flywheel.strategyState(strategy);

        uint256 diff = (rewardAmount * flywheel.ONE()) / (uint256(userBalance1) + userBalance2);

        require(index == flywheel.ONE() + diff);
        require(flywheel.userIndex(strategy, user) == index);
        require(flywheel.userIndex(strategy, user2) == index);
        require(flywheel.rewardsAccrued(user) == (diff * userBalance1) / flywheel.ONE());
        require(flywheel.rewardsAccrued(user2) == (diff * userBalance2) / flywheel.ONE());
        require(accrued1 == (diff * userBalance1) / flywheel.ONE());
        require(accrued2 == (diff * userBalance2) / flywheel.ONE());

        require(rewardToken.balanceOf(address(rewards)) == rewardAmount);
    }

    function testAccrueBeforeAddStrategy(uint128 mintAmount, uint128 rewardAmount) public {
        strategy.mint(user, mintAmount);

        rewardToken.mint(address(rewards), rewardAmount);
        rewards.setRewardsAmount(strategy, rewardAmount);

        require(flywheel.accrue(strategy, user) == 0);
    }

    function testAccrueTwoUsersBeforeAddStrategy() public {
        strategy.mint(user, 1 ether);
        strategy.mint(user2, 3 ether);

        rewardToken.mint(address(rewards), 10 ether);
        rewards.setRewardsAmount(strategy, 10 ether);

        (uint256 accrued1, uint256 accrued2) = flywheel.accrue(strategy, user, user2);

        require(accrued1 == 0);
        require(accrued2 == 0);
    }

    function testAccrueTwoUsersSeparately() public {
        strategy.mint(user, 1 ether);
        strategy.mint(user2, 3 ether);

        rewardToken.mint(address(rewards), 10 ether);
        rewards.setRewardsAmount(strategy, 10 ether);

        flywheel.addStrategyForRewards(strategy);

        uint256 accrued = flywheel.accrue(strategy, user);

        rewards.setRewardsAmount(strategy, 0);

        uint256 accrued2 = flywheel.accrue(strategy, user2);

        (uint224 index, ) = flywheel.strategyState(strategy);

        require(index == flywheel.ONE() + 2.5 ether);
        require(flywheel.userIndex(strategy, user) == index);
        require(flywheel.rewardsAccrued(user) == 2.5 ether);
        require(flywheel.rewardsAccrued(user2) == 7.5 ether);
        require(accrued == 2.5 ether);
        require(accrued2 == 7.5 ether);

        require(rewardToken.balanceOf(address(rewards)) == 10 ether);
    }

    function testAccrueSecondUserLater() public {
        strategy.mint(user, 1 ether);

        rewardToken.mint(address(rewards), 10 ether);
        rewards.setRewardsAmount(strategy, 10 ether);

        flywheel.addStrategyForRewards(strategy);

        (uint256 accrued, uint256 accrued2) = flywheel.accrue(strategy, user, user2);

        (uint224 index, ) = flywheel.strategyState(strategy);

        require(index == flywheel.ONE() + 10 ether);
        require(flywheel.userIndex(strategy, user) == index);
        require(flywheel.rewardsAccrued(user) == 10 ether);
        require(flywheel.rewardsAccrued(user2) == 0);
        require(accrued == 10 ether);
        require(accrued2 == 0);

        require(rewardToken.balanceOf(address(rewards)) == 10 ether);

        strategy.mint(user2, 3 ether);

        rewardToken.mint(address(rewards), 4 ether);
        rewards.setRewardsAmount(strategy, 4 ether);

        (accrued, accrued2) = flywheel.accrue(strategy, user, user2);

        (index, ) = flywheel.strategyState(strategy);

        require(index == flywheel.ONE() + 11 ether);
        require(flywheel.userIndex(strategy, user) == index);
        require(flywheel.rewardsAccrued(user) == 11 ether);
        require(flywheel.rewardsAccrued(user2) == 3 ether);
        require(accrued == 11 ether);
        require(accrued2 == 3 ether);

        require(rewardToken.balanceOf(address(rewards)) == 14 ether);
    }

    function testClaim(
        uint128 userBalance1,
        uint128 userBalance2,
        uint128 rewardAmount
    ) public {
        hevm.assume(userBalance1 != 0 && userBalance2 != 0 && rewardAmount != 0);

        testAccrue(userBalance1, userBalance2, rewardAmount);
        flywheel.claimRewards(user);

        uint256 diff = (rewardAmount * flywheel.ONE()) / (uint256(userBalance1) + userBalance2);
        uint256 accrued = (diff * userBalance1) / flywheel.ONE();

        require(rewardToken.balanceOf(address(rewards)) == rewardAmount - accrued);
        require(rewardToken.balanceOf(user) == accrued);
        require(flywheel.rewardsAccrued(user) == 0);

        flywheel.claimRewards(user);
    }

    function testBoost(
        uint128 userBalance1,
        uint128 userBalance2,
        uint128 rewardAmount,
        uint128 boost
    ) public {
        hevm.assume(userBalance1 != 0 && userBalance2 != 0 && rewardAmount != 0);

        booster.setBoost(user, boost);

        flywheel.setBooster(IFlywheelBooster(address(booster)));

        strategy.mint(user, userBalance1);
        strategy.mint(user2, userBalance2);

        rewardToken.mint(address(rewards), rewardAmount);
        rewards.setRewardsAmount(strategy, rewardAmount);

        flywheel.addStrategyForRewards(strategy);

        uint256 accrued = flywheel.accrue(strategy, user);

        (uint224 index, ) = flywheel.strategyState(strategy);

        uint256 diff = (rewardAmount * flywheel.ONE()) / (uint256(userBalance1) + userBalance2 + boost);
        uint256 user1Boosted = uint256(userBalance1) + boost;

        require(index == flywheel.ONE() + diff);
        require(flywheel.userIndex(strategy, user) == index);
        require(flywheel.rewardsAccrued(user) == (diff * user1Boosted) / flywheel.ONE());
        require(accrued == (diff * user1Boosted) / flywheel.ONE());

        require(flywheel.rewardsAccrued(user2) == 0 ether);

        require(rewardToken.balanceOf(address(rewards)) == rewardAmount);
    }
}
