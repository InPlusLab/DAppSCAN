/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {Beneficiary} from "../Beneficiary.sol";
import {MonetaryTypesLib} from "../MonetaryTypesLib.sol";

/**
 * @title MockedTokenHolderRevenueFund
 * @notice Mocked implementation of TokenHolderRevenueFund
 */
contract MockedTokenHolderRevenueFund /*is Beneficiary*/ {
    //
    // Types
    // -----------------------------------------------------------------------------------------------------------------
    struct ClaimTransfer {
        Beneficiary beneficiary;
        address destWallet;
        string balanceType;
        MonetaryTypesLib.Currency currency;
        string standard;
    }

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    ClaimTransfer[] public _claimTransfers;

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function _reset()
    public
    {
        _claimTransfers.length = 0;
    }

    function claimAndTransferToBeneficiary(Beneficiary beneficiary, address destWallet, string balanceType,
        address currencyCt, uint256 currencyId, string standard)
    public
    {
        _claimTransfers.push(
            ClaimTransfer(
                beneficiary, destWallet, balanceType, MonetaryTypesLib.Currency(currencyCt, currencyId), standard
            )
        );
    }

    function _getClaimTransfer(uint256 index)
    public
    view
    returns (Beneficiary beneficiary, address destWallet, string balanceType,
        address currencyCt, uint256 currencyId, string standard)
    {
        beneficiary = _claimTransfers[index].beneficiary;
        destWallet = _claimTransfers[index].destWallet;
        balanceType = _claimTransfers[index].balanceType;
        currencyCt = _claimTransfers[index].currency.ct;
        currencyId = _claimTransfers[index].currency.id;
        standard = _claimTransfers[index].standard;
    }
}