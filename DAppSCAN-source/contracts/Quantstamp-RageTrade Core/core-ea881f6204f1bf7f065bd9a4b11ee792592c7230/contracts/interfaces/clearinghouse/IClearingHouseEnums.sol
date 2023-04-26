// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IClearingHouseEnums {
    enum LimitOrderType {
        NONE,
        LOWER_LIMIT,
        UPPER_LIMIT
    }

    enum MulticallOperationType {
        UPDATE_MARGIN,
        UPDATE_PROFIT,
        SWAP_TOKEN,
        UPDATE_RANGE_ORDER,
        REMOVE_LIMIT_ORDER,
        LIQUIDATE_LIQUIDITY_POSITIONS,
        LIQUIDATE_TOKEN_POSITION
    }
}
