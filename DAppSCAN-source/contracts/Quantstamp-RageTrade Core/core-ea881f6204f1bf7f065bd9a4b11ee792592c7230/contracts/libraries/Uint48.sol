// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

/// @title Uint48 concating functions
library Uint48Lib {
    /// @notice Packs two int24 values into uint48
    /// @dev Used for concating two ticks into 48 bits value
    /// @param val1 First 24 bits value
    /// @param val2 Second 24 bits value
    /// @return concatenated value
    function concat(int24 val1, int24 val2) internal pure returns (uint48 concatenated) {
        assembly {
            concatenated := add(shl(24, val1), and(val2, 0x000000ffffff))
        }
    }

    /// @notice Unpacks uint48 into two int24 values
    /// @dev Used for unpacking 48 bits value into two 24 bits values
    /// @param concatenated 48 bits value
    /// @return val1 First 24 bits value
    /// @return val2 Second 24 bits value
    function unconcat(uint48 concatenated) internal pure returns (int24 val1, int24 val2) {
        assembly {
            val2 := concatenated
            val1 := shr(24, concatenated)
        }
    }
}
