// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { SignedMath } from '../libraries/SignedMath.sol';

/// @title Signed math functions
contract SignedMathTest {
    function abs(int256 value) external pure returns (int256) {
        return SignedMath.abs(value);
    }

    function absUint(int256 value) external pure returns (uint256) {
        return SignedMath.absUint(value);
    }

    function sign(int256 value) external pure returns (int256) {
        return SignedMath.sign(value);
    }

    /// @notice Converts a signed integer into an unsigned integer and inverts positive bool if negative
    function extractSign(int256 a, bool positive) external pure returns (uint256 _a, bool) {
        return SignedMath.extractSign(a, positive);
    }

    function extractSign(int256 a) external pure returns (uint256 _a, bool) {
        return SignedMath.extractSign(a);
    }
}
