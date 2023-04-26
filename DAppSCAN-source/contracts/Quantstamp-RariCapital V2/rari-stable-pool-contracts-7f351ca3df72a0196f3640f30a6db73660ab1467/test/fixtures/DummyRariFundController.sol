// SPDX-License-Identifier: UNLICENSED
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

    /**
     * @dev Returns `_poolsByCurrency[currencyCode]`. Used by `RariFundManager` and `RariFundProxy.getRawFundBalancesAndPrices`.
     */
    function getPoolsByCurrency(string calldata currencyCode) external view returns (uint8[] memory) {
        return new uint8[](0);
    }
}
