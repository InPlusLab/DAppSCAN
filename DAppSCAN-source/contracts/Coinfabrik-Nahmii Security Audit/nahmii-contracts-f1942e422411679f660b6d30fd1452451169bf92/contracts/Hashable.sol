/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Ownable} from "./Ownable.sol";
import {Hasher} from "./Hasher.sol";

/**
 * @title Hashable
 * @notice An ownable that has a hasher property
 */
contract Hashable is Ownable {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    Hasher public hasher;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetHasherEvent(Hasher oldHasher, Hasher newHasher);

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Set the hasher contract
    /// @param newHasher The (address of) Hasher contract instance
    function setHasher(Hasher newHasher)
    public
    onlyDeployer
    notNullAddress(newHasher)
    notSameAddresses(newHasher, hasher)
    {
        //set new hasher
        Hasher oldHasher = hasher;
        hasher = newHasher;

        // Emit event
        emit SetHasherEvent(oldHasher, newHasher);
    }

    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier hasherInitialized() {
        require(hasher != address(0));
        _;
    }
}
