/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {MonetaryTypesLib} from "../MonetaryTypesLib.sol";
import {Beneficiary} from "../Beneficiary.sol";

/**
 * @title MockedClientFund
 * @notice Mocked implementation of client fund contract
 */
contract MockedClientFund {
    //
    // Types
    // -----------------------------------------------------------------------------------------------------------------
    struct Update {
        address sourceWallet;
        address targetWallet;
        MonetaryTypesLib.Figure figure;
        string standard;
        uint256 blockNumber;
    }

    struct BalanceLogEntry {
        int256 amount;
        uint256 blockNumber;
    }

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    Update[] public settledBalanceUpdates;
    Update[] public stages;
    Update[] public beneficiaryTransfers;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event LockBalancesEvent(address lockedWallet, address lockerWallet);
    event UnlockBalancesEvent(address lockedWallet, address lockerWallet);
    event UpdateSettledBalanceEvent(address wallet, int256 value, address currencyCt, uint256 currencyId);
    event StageEvent(address wallet, int256 value, address currencyCt, uint256 currencyId);

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function _reset()
    public
    {
        settledBalanceUpdates.length = 0;
        stages.length = 0;
        beneficiaryTransfers.length = 0;
    }

    function updateSettledBalance(address wallet, int256 value, address currencyCt,
        uint256 currencyId, string standard, uint256 blockNumber)
    public
    {
        settledBalanceUpdates.push(
            Update(
                wallet,
                address(0),
                MonetaryTypesLib.Figure(
                    value,
                    MonetaryTypesLib.Currency(currencyCt, currencyId)
                ),
                standard,
                blockNumber
            )
        );
        emit UpdateSettledBalanceEvent(wallet, value, currencyCt, currencyId);
    }

    function _settledBalanceUpdatesCount()
    public
    view
    returns (uint256)
    {
        return settledBalanceUpdates.length;
    }

    function _settledBalanceUpdates(uint256 index)
    public
    view
    returns (address, int256, address, uint256, string) {
        return (
        settledBalanceUpdates[index].sourceWallet,
        settledBalanceUpdates[index].figure.amount,
        settledBalanceUpdates[index].figure.currency.ct,
        settledBalanceUpdates[index].figure.currency.id,
        settledBalanceUpdates[index].standard
        );
    }

    function stage(address wallet, int256 amount, address currencyCt, uint256 currencyId,
        string standard)
    public
    {
        stages.push(
            Update(
                wallet,
                address(0),
                MonetaryTypesLib.Figure(
                    amount,
                    MonetaryTypesLib.Currency(currencyCt, currencyId)
                ),
                standard,
                0
            )
        );
        emit StageEvent(wallet, amount, currencyCt, currencyId);
    }

    function _stagesCount()
    public
    view
    returns (uint256)
    {
        return stages.length;
    }

    function _stages(uint256 index)
    public
    view
    returns (address, address, int256, address, uint256, string)
    {
        return (
        stages[index].sourceWallet,
        stages[index].targetWallet,
        stages[index].figure.amount,
        stages[index].figure.currency.ct,
        stages[index].figure.currency.id,
        stages[index].standard
        );
    }

    function transferToBeneficiary(address wallet, Beneficiary beneficiary, int256 amount,
        address currencyCt, uint256 currencyId, string standard)
    public
    {
        beneficiaryTransfers.push(
            Update(
                wallet,
                address(beneficiary),
                MonetaryTypesLib.Figure(
                    amount,
                    MonetaryTypesLib.Currency(currencyCt, currencyId)
                ),
                standard,
                0
            )
        );
    }

    function _beneficiaryTransfersCount()
    public
    view
    returns (uint256)
    {
        return beneficiaryTransfers.length;
    }

    function _beneficiaryTransfers(uint256 index)
    public
    view
    returns (address, address, int256, address, uint256, string)
    {
        return (
        beneficiaryTransfers[index].sourceWallet,
        beneficiaryTransfers[index].targetWallet,
        beneficiaryTransfers[index].figure.amount,
        beneficiaryTransfers[index].figure.currency.ct,
        beneficiaryTransfers[index].figure.currency.id,
        beneficiaryTransfers[index].standard
        );
    }
}