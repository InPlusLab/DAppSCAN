// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

contract STMXUSDAggregator {
    int256 temp = 2181088;

    function latestAnswer() external view returns (int256) {
        return temp;
    }
}
