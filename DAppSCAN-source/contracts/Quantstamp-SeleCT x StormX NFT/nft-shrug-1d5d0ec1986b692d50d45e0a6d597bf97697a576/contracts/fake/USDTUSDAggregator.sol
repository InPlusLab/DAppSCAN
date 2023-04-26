// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

contract USDTUSDAggregator {
    int256 temp = 100142638;

    function latestAnswer() external view returns (int256) {
        return temp;
    }
}
