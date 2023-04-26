// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "ds-test/test.sol";

import "../Delegator.sol";
import "../mocks/GovernanceToken.sol";

contract User {
   function doStake(Delegator d, uint256 amount) public {
      d.stake(address(this), amount);
   }

   function doRemoveStake(Delegator d, uint256 amount) public {
      d.removeStake(address(this), amount);
   }
}

contract DelegatorTest is DSTest {
   address delegatee = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
   Delegator delegator;
   GovernanceToken ctx;
   User user1;

   function setUp() public {
      ctx = new GovernanceToken(address(this), address(this), block.timestamp);
      delegator = new Delegator(delegatee, address(ctx));
      user1 = new User();
   }

   function test_parameters() public {
      assertEq(delegator.owner(), address(this));
      assertEq(delegator.delegatee(), delegatee);
      assertEq(delegator.token(), address(ctx));
      assertEq(ctx.delegates(address(delegator)), delegatee);
   }

   function test_stake(address staker, uint256 amount) public {
      if (amount >= ctx.totalSupply()) return;
      if (staker == address(0)) return;
      assertEq(delegator.stakerBalance((staker)), 0);
      delegator.stake(staker, amount);
      assertEq(delegator.stakerBalance((staker)), amount);
      ctx.transfer(address(delegator), amount); //simulate transfer from owner
      assertEq(ctx.getCurrentVotes(delegatee), amount);
      assertEq(ctx.balanceOf(address(delegator)), amount);
   }

   function testFail_stake_notOwner(uint256 amount) public {
      user1.doStake(delegator, amount);
   }

   function test_removeStake(address staker, uint256 amount) public {
      if (amount >= ctx.totalSupply()) return;
      if (staker == address(0)) return;
      ctx.transfer(address(delegator), amount); //simulate transfer from owner
      delegator.stake(staker, amount);
      assertEq(ctx.getCurrentVotes(delegatee), amount);
      assertEq(delegator.stakerBalance((staker)), amount);
      assertEq(ctx.balanceOf(address(delegator)), amount);
      delegator.removeStake(staker, amount);
      assertEq(ctx.getCurrentVotes(delegatee), 0);
      assertEq(delegator.stakerBalance((staker)), 0);
      assertEq(ctx.balanceOf(address(delegator)), 0);
      assertEq(ctx.balanceOf(staker), amount);
   }

   function testFail_removeStake_notOwner(uint256 amount) public {
      ctx.transfer(address(delegator), amount); //simulate transfer from owner
      delegator.stake(address(user1), amount);
      user1.doRemoveStake(delegator, amount);
   }

   function testFail_removeStake_notEnoughBalance(uint256 amount) public {
      ctx.transfer(address(delegator), amount); //simulate transfer from owner
      delegator.stake(address(user1), amount);
      delegator.removeStake(address(user1), amount + 1);
   }
}
