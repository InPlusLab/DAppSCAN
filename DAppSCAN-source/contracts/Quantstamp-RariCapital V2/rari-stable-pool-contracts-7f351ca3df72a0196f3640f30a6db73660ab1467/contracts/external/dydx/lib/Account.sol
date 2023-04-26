// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

/**
 * @title Account
 * @author dYdX
 *
 * Library of structs and functions that represent an account
 */
library Account {
    // Represents the unique key that specifies an account
    struct Info {
        address owner;  // The address that owns the account
        uint256 number; // A nonce that allows a single address to control many accounts
    }
}
