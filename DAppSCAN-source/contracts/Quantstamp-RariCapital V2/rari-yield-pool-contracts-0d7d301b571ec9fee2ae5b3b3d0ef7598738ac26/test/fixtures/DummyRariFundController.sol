/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public (i.e., non-administrative) application programming interfaces (APIs) of the official Ethereum smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license), provided that the application does not abuse the APIs or act against the interests of Rari Capital, Inc.
 * Anyone is free to study, review, and analyze the source code contained in this package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in this package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

/**
 * @title DummyRariFundController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This contract is a dummy upgrade of RariFundController for testing.
 */
contract DummyRariFundController {
    /**
     * @dev Boolean to be checked on `upgradeFundController`.
     */
    bool public constant IS_RARI_FUND_CONTROLLER = true;

    /**
     * @dev Returns the balances of all currencies supported dYdX.
     */
    function getDydxBalances() external view returns (address[] memory, uint256[] memory) {
        return (new address[](0), new uint256[](0));
    }

    /**
     * @dev Returns the fund controller's balance of the specified currency in the specified pool.
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `CompoundPoolController.getBalance`) potentially modifies the state.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token.
     */
    function _getPoolBalance(uint8 pool, string memory currencyCode) public returns (uint256) {
        return 0;
    }

    /**
     * @dev Returns the fund controller's balance of the specified currency in the specified pool.
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `CompoundPoolController.getBalance`) potentially modifies the state.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token.
     */
    function getPoolBalance(uint8 pool, string memory currencyCode) public returns (uint256) {
        return _getPoolBalance(pool, currencyCode);
    }

    /**
     * @dev Return a boolean indicating if the fund controller has funds in `currencyCode` in `pool`.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be approved.
     */
    function hasCurrencyInPool(uint8 pool, string calldata currencyCode) external view returns (bool) {
        return false;
    }
}
