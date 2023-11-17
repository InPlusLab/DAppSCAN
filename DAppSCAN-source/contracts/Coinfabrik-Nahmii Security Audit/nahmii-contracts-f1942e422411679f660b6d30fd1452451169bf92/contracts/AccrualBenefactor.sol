/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Benefactor} from "./Benefactor.sol";
import {SafeMathIntLib} from "./SafeMathIntLib.sol";
import {ConstantsLib} from "./ConstantsLib.sol";

/**
 * @title AccrualBenefactor
 * @notice A benefactor whose registered beneficiaries obtain a predefined fraction of total amount
 */
contract AccrualBenefactor is Benefactor {
    using SafeMathIntLib for int256;

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    mapping(address => int256) private _beneficiaryFractionMap;
    int256 public totalBeneficiaryFraction;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event RegisterAccrualBeneficiaryEvent(address beneficiary, int256 fraction);
    event DeregisterAccrualBeneficiaryEvent(address beneficiary);

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Register the given beneficiary for the entirety fraction
    /// @param beneficiary Address of beneficiary to be registered
    function registerBeneficiary(address beneficiary)
    public
    onlyDeployer
    notNullAddress(beneficiary)
    returns (bool)
    {
        return registerFractionalBeneficiary(beneficiary, ConstantsLib.PARTS_PER());
    }

    /// @notice Register the given beneficiary for the given fraction
    /// @param beneficiary Address of beneficiary to be registered
    /// @param fraction Fraction of benefits to be given
    function registerFractionalBeneficiary(address beneficiary, int256 fraction)
    public
    onlyDeployer
    notNullAddress(beneficiary)
    returns (bool)
    {
        require(fraction > 0);
        require(totalBeneficiaryFraction.add(fraction) <= ConstantsLib.PARTS_PER());

        if (!super.registerBeneficiary(beneficiary))
            return false;

        _beneficiaryFractionMap[beneficiary] = fraction;
        totalBeneficiaryFraction = totalBeneficiaryFraction.add(fraction);

        // Emit event
        emit RegisterAccrualBeneficiaryEvent(beneficiary, fraction);

        return true;
    }

    /// @notice Deregister the given beneficiary
    /// @param beneficiary Address of beneficiary to be deregistered
    function deregisterBeneficiary(address beneficiary)
    public
    onlyDeployer
    notNullAddress(beneficiary)
    returns (bool)
    {
        if (!super.deregisterBeneficiary(beneficiary))
            return false;

        totalBeneficiaryFraction = totalBeneficiaryFraction.sub(_beneficiaryFractionMap[beneficiary]);
        _beneficiaryFractionMap[beneficiary] = 0;

        // Emit event
        emit DeregisterAccrualBeneficiaryEvent(beneficiary);

        return true;
    }

    /// @notice Get the fraction of benefits that is granted the given beneficiary
    /// @param beneficiary Address of beneficiary
    /// @return The beneficiary's fraction
    function beneficiaryFraction(address beneficiary)
    public
    view
    returns (int256)
    {
        return _beneficiaryFractionMap[beneficiary];
    }
}
