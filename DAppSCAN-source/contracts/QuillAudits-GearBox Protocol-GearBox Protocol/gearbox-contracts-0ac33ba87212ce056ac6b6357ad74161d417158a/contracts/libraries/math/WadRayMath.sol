// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.4;


import {Errors} from "../helpers/Errors.sol";

/**
 * @title WadRayMath library
 * @author Aave
 * @dev Provides mul and div function for wads (decimal numbers with 18 digits precision) and rays (decimals with 27 digits)
 * More info https://github.com/aave/aave-protocol/blob/master/contracts/libraries/WadRayMath.sol
 */

library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant halfWAD = WAD / 2;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant halfRAY = RAY / 2;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    /**
     * @return One ray, 1e27
     */
    function ray() internal pure returns (uint256) {
        return RAY; // T:[WRM-1]
    }

    /**
     * @return One wad, 1e18
     */

    function wad() internal pure returns (uint256) {
        return WAD; // T:[WRM-1]
    }

    /**
     * @return Half ray, 1e27/2
     */
    function halfRay() internal pure returns (uint256) {
        return halfRAY; // T:[WRM-2]
    }

    /**
     * @return Half ray, 1e18/2
     */
    function halfWad() internal pure returns (uint256) {
        return halfWAD; // T:[WRM-2]
    }

    /**
     * @dev Multiplies two wad, rounding half up to the nearest wad
     * @param a Wad
     * @param b Wad
     * @return The result of a*b, in wad
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0; // T:[WRM-3]
        }

        require(
            a <= (type(uint256).max - halfWAD) / b,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        ); // T:[WRM-3]

        return (a * b + halfWAD) / WAD; // T:[WRM-3]
    }

    /**
     * @dev Divides two wad, rounding half up to the nearest wad
     * @param a Wad
     * @param b Wad
     * @return The result of a/b, in wad
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO); // T:[WRM-4]
        uint256 halfB = b / 2;

        require(
            a <= (type(uint256).max - halfB) / WAD,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        ); // T:[WRM-4]

        return (a * WAD + halfB) / b; // T:[WRM-4]
    }

    /**
     * @dev Multiplies two ray, rounding half up to the nearest ray
     * @param a Ray
     * @param b Ray
     * @return The result of a*b, in ray
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0; // T:[WRM-5]
        }

        require(
            a <= (type(uint256).max - halfRAY) / b,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        ); // T:[WRM-5]

        return (a * b + halfRAY) / RAY; // T:[WRM-5]
    }

    /**
     * @dev Divides two ray, rounding half up to the nearest ray
     * @param a Ray
     * @param b Ray
     * @return The result of a/b, in ray
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO); // T:[WRM-6]
        uint256 halfB = b / 2; // T:[WRM-6]

        require(
            a <= (type(uint256).max - halfB) / RAY,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        ); // T:[WRM-6]

        return (a * RAY + halfB) / b; // T:[WRM-6]
    }

    /**
     * @dev Casts ray down to wad
     * @param a Ray
     * @return a casted to wad, rounded half up to the nearest wad
     */
    function rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfRatio = WAD_RAY_RATIO / 2; // T:[WRM-7]
        uint256 result = halfRatio + a; // T:[WRM-7]
        require(result >= halfRatio, Errors.MATH_ADDITION_OVERFLOW); // T:[WRM-7]

        return result / WAD_RAY_RATIO; // T:[WRM-7]
    }

    /**
     * @dev Converts wad up to ray
     * @param a Wad
     * @return a converted in ray
     */
    function wadToRay(uint256 a) internal pure returns (uint256) {
        uint256 result = a * WAD_RAY_RATIO; // T:[WRM-8]
        require(
            result / WAD_RAY_RATIO == a,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        ); // T:[WRM-8]
        return result; // T:[WRM-8]
    }
}
