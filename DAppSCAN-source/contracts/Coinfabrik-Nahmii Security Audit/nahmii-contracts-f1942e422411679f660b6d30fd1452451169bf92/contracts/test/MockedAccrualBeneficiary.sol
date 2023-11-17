/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {AccrualBeneficiary} from "../AccrualBeneficiary.sol";
import {MockedBeneficiary} from "./MockedBeneficiary.sol";
import {MonetaryTypesLib} from "../MonetaryTypesLib.sol";

/**
 * @title MockedAccrualBeneficiary
 * @notice Mocked implementation of accrual beneficiary
 */
contract MockedAccrualBeneficiary is AccrualBeneficiary, MockedBeneficiary {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    uint256 public _closedAccrualPeriodsCount;

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function _reset()
    public
    {
        super._reset();
        _closedAccrualPeriodsCount = 0;
    }

    function closeAccrualPeriod(MonetaryTypesLib.Currency[])
    public
    {
        _closedAccrualPeriodsCount++;
    }
}