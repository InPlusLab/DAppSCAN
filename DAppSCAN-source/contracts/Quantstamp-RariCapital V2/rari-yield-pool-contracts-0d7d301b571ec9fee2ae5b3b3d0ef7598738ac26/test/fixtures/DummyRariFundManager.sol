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
 * @title DummyRariFundManager
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This contract is a dummy upgrade of RariFundManager for testing.
 */
contract DummyRariFundManager {
    /**
     * @dev Old RariFundManager contract authorized to migrate its data to the new one.
     */
    address private _authorizedFundManagerDataSource;

    /**
     * @dev Upgrades RariFundManager.
     * Authorizes the source for fund manager data (i.e., the old fund manager).
     * @param authorizedFundManagerDataSource Authorized source for data (i.e., the old fund manager).
     */
    function authorizeFundManagerDataSource(address authorizedFundManagerDataSource) external {
        _authorizedFundManagerDataSource = authorizedFundManagerDataSource;
    }

    /**
     * @dev Struct for data to transfer from the old RariFundManager to the new one.
     */
    struct FundManagerData {
        int256 netDeposits;
        int256 rawInterestAccruedAtLastFeeRateChange;
        int256 interestFeesGeneratedAtLastFeeRateChange;
        uint256 interestFeesClaimed;
    }

    /**
     * @dev Upgrades RariFundManager.
     * Sets data receieved from the old contract.
     * @param data The data from the old contract necessary to initialize the new contract.
     */
    function setFundManagerData(FundManagerData calldata data) external {
        require(_authorizedFundManagerDataSource != address(0) && msg.sender == _authorizedFundManagerDataSource, "Caller is not an authorized source.");
        
        _netDeposits = data.netDeposits;
        _rawInterestAccruedAtLastFeeRateChange = data.rawInterestAccruedAtLastFeeRateChange;
        _interestFeesGeneratedAtLastFeeRateChange = data.interestFeesGeneratedAtLastFeeRateChange;
        _interestFeesClaimed = data.interestFeesClaimed;
    }

    /**
     * @dev Net quantity of deposits to the fund (i.e., deposits - withdrawals).
     * On deposit, amount deposited is added to _netDeposits; on withdrawal, amount withdrawn is subtracted from _netDeposits.
     */
    int256 private _netDeposits;

    /**
     * @dev The amount of interest accrued at the time of the most recent change to the fee rate.
     */
    int256 private _rawInterestAccruedAtLastFeeRateChange;

    /**
     * @dev The amount of fees generated on interest at the time of the most recent change to the fee rate.
     */
    int256 private _interestFeesGeneratedAtLastFeeRateChange;

    /**
     * @dev The total claimed amount of interest fees.
     */
    uint256 private _interestFeesClaimed;
}
