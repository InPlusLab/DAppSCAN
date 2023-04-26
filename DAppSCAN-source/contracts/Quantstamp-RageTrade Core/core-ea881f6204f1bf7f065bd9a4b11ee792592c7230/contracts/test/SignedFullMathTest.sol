// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { SignedFullMath } from '../libraries/SignedFullMath.sol';

contract SignedFullMathTest {
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) public pure returns (uint256 result) {
        return FullMath.mulDiv(a, b, denominator);
    }

    function mulDiv(
        int256 a,
        uint256 b,
        uint256 denominator
    ) public pure returns (int256 result) {
        return SignedFullMath.mulDiv(a, b, denominator);
    }

    function mulDiv(
        int256 a,
        int256 b,
        int256 denominator
    ) public pure returns (int256 result) {
        return SignedFullMath.mulDiv(a, b, denominator);
    }

    function mulDivRoundingUp(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) public pure returns (uint256 result) {
        return FullMath.mulDivRoundingUp(a, b, denominator);
    }

    function mulDivRoundingDown(
        int256 a,
        uint256 b,
        uint256 denominator
    ) public pure returns (int256 result) {
        return SignedFullMath.mulDivRoundingDown(a, b, denominator);
    }

    function mulDivRoundingDown(
        int256 a,
        int256 b,
        int256 denominator
    ) public pure returns (int256 result) {
        return SignedFullMath.mulDivRoundingDown(a, b, denominator);
    }
}
