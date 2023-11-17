/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Ownable} from "./Ownable.sol";
import {SecurityBond} from "./SecurityBond.sol";

/**
 * @title SecurityBondable
 * @notice An ownable that has a security bond property
 */
contract SecurityBondable is Ownable {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    SecurityBond public securityBond;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetSecurityBondEvent(SecurityBond oldSecurityBond, SecurityBond newSecurityBond);

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Set the security bond contract
    /// @param newSecurityBond The (address of) SecurityBond contract instance
    function setSecurityBond(SecurityBond newSecurityBond)
    public
    onlyDeployer
    notNullAddress(newSecurityBond)
    notSameAddresses(newSecurityBond, securityBond)
    {
        //set new security bond
        SecurityBond oldSecurityBond = securityBond;
        securityBond = newSecurityBond;

        // Emit event
        emit SetSecurityBondEvent(oldSecurityBond, newSecurityBond);
    }

    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier securityBondInitialized() {
        require(securityBond != address(0));
        _;
    }
}
