// SPDX-License-Identifier: Apache-2.0

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

/// @notice A library for performing overflow-/underflow-safe addition and subtraction on uint128.
library BoringMath128 {
    function add(uint128 a, uint128 b) internal pure returns (uint128 c) {
        require((c = a + b) >= b, "BoringMath: Add Overflow");
    }

    function sub(uint128 a, uint128 b) internal pure returns (uint128 c) {
        require((c = a - b) <= a, "BoringMath: Underflow");
    }
}
