// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

contract ETHUSDAggregator {
    int256 temp = 250729030969;

    function latestAnswer() external view returns (int256) {
        return temp;
    }
}
