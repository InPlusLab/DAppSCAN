// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;


interface IStaking{
    
    
    function stakeForUser(address user, uint256 lockUp) external
        returns (
            uint256 level,
            uint256 totalStakedForUser,
            bool first_lock,
            bool second_lock,
            bool third_lock,
            bool fourth_lock,
            uint256 amountLock,
            uint256 rewardTaken,
            uint256 enteredAt
        );

    function addPresale(address presale) external;

    function addReLock(address user) external;
}