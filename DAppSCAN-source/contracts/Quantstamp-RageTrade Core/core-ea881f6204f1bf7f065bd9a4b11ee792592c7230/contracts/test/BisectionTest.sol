// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Bisection } from '../libraries/Bisection.sol';

contract BisectionTest {
    function increasingFunction(uint160 val) public pure returns (uint256) {
        return (val * 3);
    }

    function findSolution(
        uint256 y_target,
        uint160 x_lower,
        uint160 x_upper
    ) external pure returns (uint160) {
        return Bisection.findSolution(increasingFunction, y_target, x_lower, x_upper);
    }
}
