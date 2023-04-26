// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;


/**
 * The purpose of this contract is to hold BAI tokens for gas compensation:
 * https://github.com/liquity/dev#gas-compensation
 * When a borrower opens a vault, an additional 50 BAI debt is issued,
 * and 50 BAI is minted and sent to this contract.
 * When a borrower closes their active vault, this gas compensation is refunded:
 * 50 BAI is burned from the this contract's balance, and the corresponding
 * 50 BAI debt on the vault is cancelled.
 * See this issue for more context: https://github.com/liquity/dev/issues/186
 */
contract GasPool {
    // do nothing, as the core contracts have permission to send to and burn from this address
}
