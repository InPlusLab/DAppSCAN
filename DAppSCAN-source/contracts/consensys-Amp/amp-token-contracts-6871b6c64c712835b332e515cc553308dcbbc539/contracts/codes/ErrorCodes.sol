// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;


/**
 * @title ErrorCodes
 * @notice Amp error codes.
 */
contract ErrorCodes {
    string internal EC_50_TRANSFER_FAILURE = "50";
    string internal EC_51_TRANSFER_SUCCESS = "51";
    string internal EC_52_INSUFFICIENT_BALANCE = "52";
    string internal EC_53_INSUFFICIENT_ALLOWANCE = "53";

    string internal EC_56_INVALID_SENDER = "56";
    string internal EC_57_INVALID_RECEIVER = "57";
    string internal EC_58_INVALID_OPERATOR = "58";

    string internal EC_59_INSUFFICIENT_RIGHTS = "59";

    string internal EC_5A_INVALID_SWAP_TOKEN_ADDRESS = "5A";
    string internal EC_5B_INVALID_VALUE_0 = "5B";
    string internal EC_5C_ADDRESS_CONFLICT = "5C";
    string internal EC_5D_PARTITION_RESERVED = "5D";
    string internal EC_5E_PARTITION_PREFIX_CONFLICT = "5E";
    string internal EC_5F_INVALID_PARTITION_PREFIX_0 = "5F";
}
