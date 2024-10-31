// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;


library ExchangeConstants {
    uint256 internal constant _MIN_LEFTOVER_REFERRAL_SHARE = 0.5e18; // 50%
    uint256 internal constant _MAX_LEFTOVER_REFERRAL_SHARE = 1e18; // 100%
    uint256 internal constant _DEFAULT_LEFTOVER_REFERRAL_SHARE = 1e18; // 100%
}
