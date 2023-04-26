// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

int256 constant ONE = 1;

/// @title Signed math functions
library SignedMath {
    function abs(int256 value) internal pure returns (int256) {
        return value > 0 ? value : -value;
    }

    function absUint(int256 value) internal pure returns (uint256) {
        return uint256(abs(value));
    }

    function sign(int256 value) internal pure returns (int256) {
        return value >= 0 ? ONE : -ONE;
    }

    /// @notice Converts a signed integer into an unsigned integer and inverts positive bool if negative
    function extractSign(int256 a, bool positive) internal pure returns (uint256 _a, bool) {
        if (a < 0) {
            positive = !positive;
            _a = uint256(-a);
        } else {
            _a = uint256(a);
        }
        return (_a, positive);
    }

    function extractSign(int256 a) internal pure returns (uint256 _a, bool) {
        return extractSign(a, true);
    }

    /// @notice returns the max of two int256 numbers
    /// @param a first number
    /// @param b second number
    /// @return c  = max of a and b
    function max(int256 a, int256 b) internal pure returns (int256 c) {
        if (a > b) c = a;
        else c = b;
    }
}
