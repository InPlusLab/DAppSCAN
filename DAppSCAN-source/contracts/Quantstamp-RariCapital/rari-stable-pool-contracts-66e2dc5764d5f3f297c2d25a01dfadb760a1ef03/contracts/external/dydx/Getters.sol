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

import { Account } from "./lib/Account.sol";
import { Types } from "./lib/Types.sol";


/**
 * @title Getters
 * @author dYdX
 *
 * Public read-only functions that allow transparency into the state of Solo
 */
contract Getters {
    using Types for Types.Par;

    /**
     * Get an account's summary for each market.
     *
     * @param  account  The account to query
     * @return          The following values:
     *                   - The ERC20 token address for each market
     *                   - The account's principal value for each market
     *                   - The account's (supplied or borrowed) number of tokens for each market
     */
    function getAccountBalances(
        Account.Info memory account
    )
        public
        view
        returns (
            address[] memory,
            Types.Par[] memory,
            Types.Wei[] memory
        );
}
