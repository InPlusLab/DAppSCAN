//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

library ExtendedMath {
    /**
     * @return The given number raised to the power of 2
     */
    function pow2(int256 a) internal pure returns (int256) {
        if (a == 0) {
            return 0;
        }
        int256 c = a * a;
        require(c / a == a, "ExtendedMath: squaring overflow");
        return c;
    }

    function pow3(int256 a) internal pure returns (int256) {
        if (a == 0) {
            return 0;
        }
        int256 c = a * a;
        require(c / a == a, "ExtendedMath: cubing overflow2");

        int256 d = c * a;
        require(d / a == c, "ExtendedMath: cubing overflow3");
        return d;
    }

    /**
     * @return z The square root of the given positive number
     */
    function sqrt(int256 y) internal pure returns (int256 z) {
        require(y >= 0, "Negative sqrt");
        if (y > 3) {
            z = y;
            int256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
