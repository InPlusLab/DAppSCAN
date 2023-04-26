// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "./helpers/Helpers.sol";
import "../utils/ABDKMath64x64.sol";

contract StakeTest is DSTest {
    using ABDKMath64x64 for int128;

    uint256 constant BRONZE_STAKE = 100 * 10**18;
    uint48  constant BRONZE_TIME  = 10 days;

    uint256 constant SILVER_STAKE = 1000 * 10**18;
    uint48  constant SILVER_TIME  = 20 days;

    uint256 constant GOLD_STAKE   = 10000 * 10**18;
    uint48  constant GOLD_TIME    = 30 days;

    uint256 constant MONTHLY_REWARD     = 210_000 * 10**18;
    uint256 constant REWARDS_PER_SECOND = MONTHLY_REWARD / 30 days;

    function setUp() public {
        AppStorage storage s = th.apps();
        s.cheats = CheatCodes(HEVM_ADDRESS);
        s.cheats.warp(1644132849);

        th.setAddresses();
        th.deployRegistry();
        th.deployTokens();


        PassRequirement memory bronze = PassRequirement({
        veteranCount: 0,
        retiredCount: 0,
        stakeTime:    BRONZE_TIME,
        stakeAmount:  BRONZE_STAKE 
        });

        PassRequirement memory silver = PassRequirement({
        veteranCount: 0,
        retiredCount: 0,
        stakeTime:    SILVER_TIME,
        stakeAmount:  SILVER_STAKE 
        });

        PassRequirement memory gold = PassRequirement({
        veteranCount: 0,
        retiredCount: 0,
        stakeTime:    GOLD_TIME,
        stakeAmount:  GOLD_STAKE 
        });

        PassRequirement[] memory reqs = new PassRequirement[](3);
        reqs[0] = bronze;
        reqs[1] = silver;
        reqs[2] = gold;

        th.deployStaking(REWARDS_PER_SECOND, reqs);
    }

    function test_assign_addresses() public {
        AppStorage storage s = th.apps();
        assertTrue(s.owner != address(0));
    }

    function test_alice_enter_stake() public {
        AppStorage storage s = th.apps();

        // Owner loads monthly reward
        s.cheats.prank(s.owner);
        s.sp20.transfer(address(s.staking), MONTHLY_REWARD);

        // Send Alice tokens to stake
        s.cheats.prank(s.owner);
        s.sp20.transfer(s.alice, BRONZE_STAKE);

        // Alice enters stake
        s.cheats.startPrank(s.alice);
        s.sp20.approve(address(s.staking), BRONZE_STAKE);
        s.staking.enterStake(1, BRONZE_STAKE, 10 days);
        s.cheats.stopPrank();

        assertEq(s.sp20.balanceOf(s.alice), 0);
        
        int128 coeff = s.staking.getCoefficient(s.alice);
        assertEq(coeff.toUInt(), 1);
    }

    function test_alice_exit_stake() public {
        test_alice_enter_stake();

        // Fast forward 10 days
        AppStorage storage s = th.apps();
        s.cheats.warp(block.timestamp + 10 days);

        // Assert pending reward
        uint256 pendingRewards = s.staking.pendingRewards(s.alice);
        assertEq(pendingRewards, REWARDS_PER_SECOND * 10 days);

        // Alice exits stake
        s.cheats.prank(s.alice);
        s.staking.exitStake();

        // Assert allowance of Alice
        uint256 allowance = s.sp20.allowance(address(s.staking), s.alice);
        assertEq(allowance, pendingRewards + BRONZE_STAKE);

        // Alice check-outs, assert balance of Alice
        s.cheats.prank(s.alice);
        s.sp20.transferFrom(address(s.staking), s.alice, allowance);
        assertEq(s.sp20.balanceOf(s.alice), allowance);
    }

    function test_alice_pending_rewards() public {
        test_alice_enter_stake();

        // Fast forward 5 days
        AppStorage storage s = th.apps();
        s.cheats.warp(block.timestamp + 5 days);

        // Assert pending reward
        uint256 pendingRewards = s.staking.pendingRewards(s.alice);
        assertEq(pendingRewards, REWARDS_PER_SECOND * 5 days);

        // Alice claims the prize
        s.cheats.prank(s.alice);
        s.staking.claimPendingRewards();

        // Alice check-outs, assert balance
        s.cheats.prank(s.alice);
        s.sp20.transferFrom(address(s.staking), s.alice, pendingRewards);
        assertEq(s.sp20.balanceOf(s.alice), pendingRewards);
    }

    function test_alice_late_exit() public {
        test_alice_pending_rewards();

        // Fast forward 5 days
        AppStorage storage s = th.apps();
        s.cheats.warp(block.timestamp + 5 days);

        s.cheats.startPrank(s.alice);
        s.staking.exitStake();
        uint256 maxAllowance = s.sp20.allowance(address(s.staking), s.alice);
        s.sp20.transferFrom(address(s.staking), s.alice, maxAllowance);

        assertEq(s.sp20.balanceOf(s.alice), BRONZE_STAKE + REWARDS_PER_SECOND * 10 days);
    }
}
