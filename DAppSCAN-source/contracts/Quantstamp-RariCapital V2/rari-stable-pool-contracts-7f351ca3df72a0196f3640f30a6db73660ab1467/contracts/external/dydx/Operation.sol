// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import { Account } from "./lib/Account.sol";
import { Actions } from "./lib/Actions.sol";


/**
 * @title Operation
 * @author dYdX
 *
 * Primary public function for allowing users and contracts to manage accounts within Solo
 */
contract Operation {
    /**
     * The main entry-point to Solo that allows users and contracts to manage accounts.
     * Take one or more actions on one or more accounts. The msg.sender must be the owner or
     * operator of all accounts except for those being liquidated, vaporized, or traded with.
     * One call to operate() is considered a singular "operation". Account collateralization is
     * ensured only after the completion of the entire operation.
     *
     * @param  accounts  A list of all accounts that will be used in this operation. Cannot contain
     *                   duplicates. In each action, the relevant account will be referred-to by its
     *                   index in the list.
     * @param  actions   An ordered list of all actions that will be taken in this operation. The
     *                   actions will be processed in order.
     */
    function operate(
        Account.Info[] memory accounts,
        Actions.ActionArgs[] memory actions
    )
        public;
}
