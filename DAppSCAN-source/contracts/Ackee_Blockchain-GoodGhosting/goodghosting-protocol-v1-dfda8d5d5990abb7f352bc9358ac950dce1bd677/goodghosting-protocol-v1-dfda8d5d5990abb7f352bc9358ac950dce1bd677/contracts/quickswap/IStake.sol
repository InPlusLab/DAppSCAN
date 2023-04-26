// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.11;

abstract contract IStake {
function stake(uint256 amount) public virtual;

function exit()  public virtual;
}
