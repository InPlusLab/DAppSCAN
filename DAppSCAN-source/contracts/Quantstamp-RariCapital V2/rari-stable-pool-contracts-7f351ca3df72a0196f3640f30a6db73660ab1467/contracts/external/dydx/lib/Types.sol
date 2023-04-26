// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

/**
 * @title Types
 * @author dYdX
 *
 * Library for interacting with the basic structs used in Solo
 */
library Types {
    // ============ AssetAmount ============

    enum AssetDenomination {
        Wei, // the amount is denominated in wei
        Par  // the amount is denominated in par
    }

    enum AssetReference {
        Delta, // the amount is given as a delta from the current value
        Target // the amount is given as an exact number to end up at
    }

    struct AssetAmount {
        bool sign; // true if positive
        AssetDenomination denomination;
        AssetReference ref;
        uint256 value;
    }

    // ============ Par (Principal Amount) ============

    // Individual principal amount for an account
    struct Par {
        bool sign; // true if positive
        uint128 value;
    }

    // ============ Wei (Token Amount) ============

    // Individual token amount for an account
    struct Wei {
        bool sign; // true if positive
        uint256 value;
    }
}
