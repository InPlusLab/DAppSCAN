// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.5.17;
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
