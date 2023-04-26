// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

/// @title Bisection Method
/// @notice https://en.wikipedia.org/wiki/Bisection_method
library Bisection {
    error SolutionOutOfBounds(uint256 y_target, uint160 x_lower, uint160 x_upper);

    /// @notice Finds the solution to the equation f(x) = y_target using the bisection method
    /// @param f: strictly increasing function f: uint160 -> uint256
    /// @param y_target: the target value of f(x)
    /// @param x_lower: the lower bound for x
    /// @param x_upper: the upper bound for x
    /// @return x_target: the rounded down solution to the equation f(x) = y_target
    function findSolution(
        function(uint160) pure returns (uint256) f,
        uint256 y_target,
        uint160 x_lower,
        uint160 x_upper
    ) internal pure returns (uint160) {
        // compute y at the bounds
        uint256 y_lower = f(x_lower);
        uint256 y_upper = f(x_upper);

        // if y is out of the bounds then revert
        if (y_target < y_lower || y_target > y_upper) revert SolutionOutOfBounds(y_target, x_lower, x_upper);

        // bisect repeatedly until the solution is within an error of 1 unit
        uint256 y_mid;
        uint160 x_mid;
        while (x_upper - x_lower > 1) {
            x_mid = x_lower + (x_upper - x_lower) / 2;
            y_mid = f(x_mid);
            if (y_mid > y_target) {
                x_upper = x_mid;
                y_upper = y_mid;
            } else {
                x_lower = x_mid;
                y_lower = y_mid;
            }
        }

        // at this point, x_upper - x_lower is either 0 or 1
        // if it is 1 then check if x_upper is the solution, else return x_lower as the rounded down solution
        return x_lower != x_upper && f(x_upper) == y_target ? x_upper : x_lower;
    }
}
