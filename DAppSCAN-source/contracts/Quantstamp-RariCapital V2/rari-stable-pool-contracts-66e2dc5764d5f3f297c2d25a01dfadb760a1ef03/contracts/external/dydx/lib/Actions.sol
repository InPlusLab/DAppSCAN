/*

    Copyright 2019 dYdX Trading Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

*/

pragma solidity ^0.5.7;
pragma experimental ABIEncoderV2;

import { Types } from "./Types.sol";


/**
 * @title Actions
 * @author dYdX
 *
 * Library that defines and parses valid Actions
 */
library Actions {
    // ============ Enums ============

    enum ActionType {
        Deposit,   // supply tokens
        Withdraw,  // borrow tokens
        Transfer,  // transfer balance between accounts
        Buy,       // buy an amount of some token (externally)
        Sell,      // sell an amount of some token (externally)
        Trade,     // trade tokens against another account
        Liquidate, // liquidate an undercollateralized or expiring account
        Vaporize,  // use excess tokens to zero-out a completely negative account
        Call       // send arbitrary data to an address
    }

    // ============ Structs ============

    /*
     * Arguments that are passed to Solo in an ordered list as part of a single operation.
     * Each ActionArgs has an actionType which specifies which action struct that this data will be
     * parsed into before being processed.
     */
    struct ActionArgs {
        ActionType actionType;
        uint256 accountId;
        Types.AssetAmount amount;
        uint256 primaryMarketId;
        uint256 secondaryMarketId;
        address otherAddress;
        uint256 otherAccountId;
        bytes data;
    }
}
