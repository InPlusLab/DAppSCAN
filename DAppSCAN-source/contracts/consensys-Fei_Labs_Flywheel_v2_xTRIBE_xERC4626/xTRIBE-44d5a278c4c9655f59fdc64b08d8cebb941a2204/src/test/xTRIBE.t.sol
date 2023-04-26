// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockRewards} from "flywheel/test/mocks/MockRewards.sol";

import "flywheel/FlywheelCore.sol";
import "flywheel/rewards/FlywheelGaugeRewards.sol";
import "flywheel/test/mocks/MockRewardsStream.sol";

import "./mocks/MockSetBooster.sol";

import "../xTRIBE.sol";

// Full integration tests across Flywheel Core, Flywheel Gauge Rewards and xTRIBE
contract xTRIBETest is DSTestPlus {
    FlywheelCore flywheel;
    FlywheelGaugeRewards rewards;
    MockRewardsStream stream;

    MockERC20 strategy;
    MockERC20 rewardToken;
    MockSetBooster booster;

    xTRIBE xTribe;

    function setUp() public {
        rewardToken = new MockERC20("test token", "TKN", 18);

        strategy = new MockERC20("test strategy", "TKN", 18);

        booster = new MockSetBooster();

        flywheel = new FlywheelCore(
            rewardToken,
            MockRewards(address(0)),
            IFlywheelBooster(address(booster)),
            address(this),
            Authority(address(0))
        );

        stream = new MockRewardsStream(rewardToken, 0);

        xTribe = new xTRIBE(
            rewardToken,
            address(this),
            Authority(address(0)),
            1000, // cycle of 1000
            100 // freeze window of 100
        );

        rewards = new FlywheelGaugeRewards(
            flywheel,
            address(this),
            Authority(address(0)),
            xTribe,
            IRewardsStream(address(stream))
        );

        flywheel.setFlywheelRewards(rewards);
    }

    /**
      @notice tests the "ERC20MultiVotes" functionality of xTRIBE
      Ensures that delegations successfully apply
     */
    function testXTribeDelegations(
        address user,
        address delegate,
        uint128 mintAmount,
        uint128 delegationAmount,
        uint128 transferAmount
    ) public {
        // setup
        hevm.assume(mintAmount != 0 && transferAmount <= mintAmount);
        rewardToken.mint(user, mintAmount);
        xTribe.setMaxDelegates(1);

        // deposit to xTRIBE for user
        hevm.startPrank(user);
        rewardToken.approve(address(xTribe), mintAmount);
        xTribe.deposit(mintAmount, user);

        require(xTribe.balanceOf(user) == mintAmount);

        // expect revert and early return if user tries to delegate more than they have
        if (delegationAmount > mintAmount) {
            hevm.expectRevert(abi.encodeWithSignature("DelegationError()"));
            xTribe.delegate(delegate, delegationAmount);
            return;
        }

        // user can successfully delegate
        xTribe.delegate(delegate, delegationAmount);
        require(xTribe.userDelegatedVotes(user) == delegationAmount);
        require(xTribe.numCheckpoints(delegate) == 1);
        require(xTribe.checkpoints(delegate, 0).votes == delegationAmount);

        // roll forward and check transfer snapshot and undelegation logic
        hevm.roll(block.number + 10);
        xTribe.transfer(delegate, transferAmount);

        // If user is transferring so much that they need to undelegate, check those conditions, otherwise check assuming no change
        if (mintAmount - transferAmount < delegationAmount) {
            require(xTribe.userDelegatedVotes(user) == 0);
            require(xTribe.numCheckpoints(delegate) == 2);
            require(xTribe.checkpoints(delegate, 0).votes == delegationAmount);
            require(xTribe.checkpoints(delegate, 1).votes == 0);
        } else {
            require(xTribe.userDelegatedVotes(user) == delegationAmount);
            require(xTribe.numCheckpoints(delegate) == 1);
            require(xTribe.checkpoints(delegate, 0).votes == delegationAmount);
        }
    }

    /**
      @notice tests the "FlywheelGaugeRewards + ERC20Gauges" functionality of xTRIBE
      A single user will allocate weight across 20 gauges. 
      This user will also be hold a portion of the total strategy on each gauge.
      Lastly, the test will warp part of the way through a cycle.

      The test ensures that all 3 proportions above are accounted appropriately.
     */
    function testXTribeFlywheel(
        address user,
        address[20] memory gauges,
        uint104[20] memory gaugeAmounts,
        uint104[20] memory userGaugeBalance,
        uint104[20] memory gaugeTotalSupply,
        uint112 quantity,
        uint32 warp
    ) public {
        hevm.assume(quantity != 0);
        xTribe.setMaxGauges(20);

        // setup loop summing the gauge amounts
        uint112 sum;
        {
            address[] memory gaugeList = new address[](20);
            uint112[] memory amounts = new uint112[](20);
            for (uint256 i = 0; i < 20; i++) {
                hevm.assume(
                    gauges[i] != address(0) && // no zero gauge
                        !xTribe.isGauge(gauges[i]) && // no same gauge twice
                        gaugeTotalSupply[i] != 0 // no zero supply
                );
                userGaugeBalance[i] = uint104(
                    bound(userGaugeBalance[i], 1, gaugeTotalSupply[i])
                );
                sum += gaugeAmounts[i];
                amounts[i] = gaugeAmounts[i];
                gaugeList[i] = gauges[i];

                // add gauge and strategy
                xTribe.addGauge(gauges[i]);
                flywheel.addStrategyForRewards(ERC20(gauges[i]));

                // use the booster to virtually set the balance and totalSupply of the user
                booster.setUserBoost(
                    ERC20(gauges[i]),
                    user,
                    userGaugeBalance[i]
                );
                booster.setTotalSupplyBoost(
                    ERC20(gauges[i]),
                    gaugeTotalSupply[i]
                );
            }

            // deposit the user amount and increment the gauges
            deposit(user, sum);
            hevm.prank(user);
            xTribe.incrementGauges(gaugeList, amounts);
        }
        hevm.warp(xTribe.getGaugeCycleEnd());

        // set the rewards and queue for the rewards cycle
        rewardToken.mint(address(stream), quantity);
        stream.setRewardAmount(quantity);
        rewards.queueRewardsForCycle();

        // warp partially through cycle
        hevm.warp(block.timestamp + (warp % xTribe.gaugeCycleLength()));

        // assert gauge rewards, flywheel indices, and useer amounts all are as expected
        for (uint256 i = 0; i < 20; i++) {
            (, uint112 queued, ) = rewards.gaugeQueuedRewards(ERC20(gauges[i]));
            assertEq(
                xTribe.calculateGaugeAllocation(gauges[i], quantity),
                queued
            );
            uint256 accruedBefore = flywheel.rewardsAccrued(user);
            flywheel.accrue(ERC20(gauges[i]), user);
            uint256 diff = (((uint256(queued) *
                (warp % xTribe.gaugeCycleLength())) /
                xTribe.gaugeCycleLength()) * flywheel.ONE()) /
                gaugeTotalSupply[i];
            (uint224 index, ) = flywheel.strategyState(ERC20(gauges[i]));
            assertEq(index, flywheel.ONE() + diff);
            assertEq(
                flywheel.rewardsAccrued(user),
                accruedBefore + ((diff * userGaugeBalance[i]) / flywheel.ONE())
            );
        }
    }

    /**
     @notice test an array of 20 users allocating different amounts to different gauges.
     Includes a forward warp of [0, cycle length) each time to test different conditions
     */
    function testXTribeGauges(
        address[20] memory users,
        address[20] memory gauges,
        uint104[20] memory gaugeAmount,
        uint32[20] memory warps,
        uint128 quantity
    ) public {
        xTribe.setMaxGauges(20);
        for (uint256 i = 0; i < 20; i++) {
            uint32 warp = warps[i] % xTribe.gaugeCycleLength();
            address user = users[i];
            address gauge = gauges[i];
            xTribe.addGauge(gauge);
            uint256 shares = deposit(users[i], gaugeAmount[i]);

            uint256 userWeightBefore = xTribe.getUserWeight(user);
            uint256 gaugeWeightBefore = xTribe.getGaugeWeight(gauge);
            uint256 totalWeightBefore = xTribe.totalWeight();

            uint32 cycleEnd = xTribe.getGaugeCycleEnd();

            hevm.startPrank(user);
            // Test the two major cases of successfull increment and failed increment
            if (cycleEnd - xTribe.incrementFreezeWindow() <= block.timestamp) {
                hevm.expectRevert(
                    abi.encodeWithSignature("IncrementFreezeError()")
                );
                xTribe.incrementGauge(gauge, uint112(shares));
                require(xTribe.getUserWeight(user) == userWeightBefore);
                require(xTribe.getGaugeWeight(gauge) == gaugeWeightBefore);
                require(xTribe.totalWeight() == totalWeightBefore);

                hevm.warp(block.timestamp + warp);
            } else {
                xTribe.incrementGauge(gauge, uint112(shares));
                require(
                    xTribe.storedTotalWeight() == 0 ||
                        xTribe.calculateGaugeAllocation(gauge, quantity) ==
                        (gaugeWeightBefore * quantity) /
                            xTribe.storedTotalWeight()
                );
                require(
                    xTribe.getUserWeight(user) == userWeightBefore + shares
                );
                require(
                    xTribe.getGaugeWeight(gauge) == gaugeWeightBefore + shares
                );
                require(xTribe.totalWeight() == totalWeightBefore + shares);

                hevm.warp(block.timestamp + warp);
                if (block.timestamp >= cycleEnd) {
                    require(
                        xTribe.getStoredGaugeWeight(gauge) ==
                            gaugeWeightBefore + shares
                    );
                    require(
                        xTribe.calculateGaugeAllocation(gauge, quantity) ==
                            ((gaugeWeightBefore + shares) * quantity) /
                                xTribe.storedTotalWeight()
                    );
                }
            }
            hevm.stopPrank();
        }
    }

    /**
     @notice test the xTRIBE rewards accrual over a cycle
     */
    function testXTribeRewards(
        address user1,
        address user2,
        uint128 user1Amount,
        uint128 user2Amount,
        uint128 rewardAmount,
        uint32 rewardTimestamp,
        uint32 user2DepositTimestamp
    ) public {
        rewardTimestamp = rewardTimestamp % xTribe.rewardsCycleLength();
        user2DepositTimestamp =
            user2DepositTimestamp %
            xTribe.rewardsCycleLength();
        hevm.assume(
            user1Amount != 0 &&
                user2Amount != 0 &&
                user2Amount != type(uint128).max &&
                rewardAmount != 0 &&
                rewardTimestamp <= user2DepositTimestamp &&
                user1Amount < type(uint128).max / user2Amount
        );

        rewardToken.mint(user1, user1Amount);
        rewardToken.mint(user2, user2Amount);

        hevm.startPrank(user1);
        rewardToken.approve(address(xTribe), user1Amount);
        xTribe.deposit(user1Amount, user1);
        hevm.stopPrank();

        require(xTribe.previewRedeem(user1Amount) == user1Amount);

        hevm.warp(rewardTimestamp);
        rewardToken.mint(address(xTribe), rewardAmount);
        xTribe.syncRewards();

        require(xTribe.previewRedeem(user1Amount) == user1Amount);

        hevm.warp(user2DepositTimestamp);

        hevm.startPrank(user2);
        rewardToken.approve(address(xTribe), user2Amount);
        if (xTribe.convertToShares(user2Amount) == 0) {
            hevm.expectRevert(bytes("ZERO_SHARES"));
            xTribe.deposit(user2Amount, user2);
            return;
        }
        uint256 shares2 = xTribe.deposit(user2Amount, user2);
        hevm.stopPrank();

        assertApproxEq(
            xTribe.previewRedeem(shares2),
            user2Amount,
            (xTribe.totalAssets() / xTribe.totalSupply()) + 1
        );

        uint256 effectiveCycleLength = xTribe.rewardsCycleLength() -
            rewardTimestamp;
        uint256 beforeUser2Time = user2DepositTimestamp - rewardTimestamp;
        uint256 beforeUser2Rewards = (rewardAmount * beforeUser2Time) /
            effectiveCycleLength;

        assertApproxEq(
            xTribe.previewRedeem(user1Amount),
            user1Amount + beforeUser2Rewards,
            (xTribe.totalAssets() / xTribe.totalSupply()) + 1
        );

        hevm.warp(xTribe.rewardsCycleEnd());

        uint256 remainingRewards = rewardAmount - beforeUser2Rewards;
        uint256 user1Rewards = (remainingRewards * user1Amount) /
            (user1Amount + shares2);
        uint256 user2Rewards = (remainingRewards * shares2) /
            (user1Amount + shares2);

        hevm.assume(shares2 < type(uint128).max / xTribe.totalAssets());
        assertApproxEq(
            xTribe.previewRedeem(shares2),
            user2Amount + user2Rewards,
            (xTribe.totalAssets() / xTribe.totalSupply()) + 1
        );

        hevm.assume(user1Amount < type(uint128).max / xTribe.totalAssets());
        assertApproxEq(
            xTribe.previewRedeem(user1Amount),
            user1Amount + beforeUser2Rewards + user1Rewards,
            (xTribe.totalAssets() / xTribe.totalSupply()) + 1
        );
    }

    function deposit(address user, uint256 mintAmount)
        internal
        returns (uint256 shares)
    {
        hevm.assume(xTribe.previewDeposit(mintAmount) != 0);

        rewardToken.mint(user, mintAmount);

        hevm.startPrank(user);
        rewardToken.approve(address(xTribe), mintAmount);
        shares = xTribe.deposit(mintAmount, user);
        hevm.stopPrank();
    }
}
