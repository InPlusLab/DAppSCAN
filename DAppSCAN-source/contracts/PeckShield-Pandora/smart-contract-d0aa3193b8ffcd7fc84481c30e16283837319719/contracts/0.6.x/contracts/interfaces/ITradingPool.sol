//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
interface ITradingPool {
    function enter(
        address account,
        address input,
        address output,
        uint256 amount
    ) external returns (bool);
}