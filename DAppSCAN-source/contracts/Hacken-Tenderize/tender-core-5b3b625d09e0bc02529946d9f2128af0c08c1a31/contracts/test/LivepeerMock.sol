// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockStaking.sol";

contract LivepeerMock is MockStaking {
    constructor(IERC20 _token) MockStaking(_token) {}

    function bond(uint256 _amount, address _to) external reverted(this.bond.selector) {
        require(token.transferFrom(msg.sender, address(this), _amount));
        staked += _amount;
    }

    function unbond(uint256 _amount) external reverted(this.unbond.selector) {
        staked -= _amount;
        unstakeLocks[nextUnstakeLockID] = UnstakeLock({ amount: _amount, account: msg.sender });
        nextUnstakeLockID++;
    }

    function rebondFromUnbonded(address _to, uint256 _unbondingLockId) external {
        return;
    }

    function withdrawStake(uint256 _unbondingLockId) external reverted(this.withdrawStake.selector) {
        token.transfer(unstakeLocks[_unbondingLockId].account, unstakeLocks[_unbondingLockId].amount);
    }

    function withdrawFees() external reverted(this.withdrawFees.selector) {
        staked += secondaryRewards;
        secondaryRewards = 0;
    }

    function pendingFees(address _delegator, uint256 _endRound) external view returns (uint256) {
        return secondaryRewards;
    }

    function pendingStake(address _delegator, uint256 _endRound) external view returns (uint256) {
        return staked;
    }
}
