/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Ownable} from "./Ownable.sol";
import {FraudChallenge} from "./FraudChallenge.sol";

/**
 * @title FraudChallengable
 * @notice An ownable that has a fraud challenge property
 */
contract FraudChallengable is Ownable {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    FraudChallenge public fraudChallenge;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetFraudChallengeEvent(FraudChallenge oldFraudChallenge, FraudChallenge newFraudChallenge);

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Set the fraud challenge contract
    /// @param newFraudChallenge The (address of) FraudChallenge contract instance
    function setFraudChallenge(FraudChallenge newFraudChallenge)
    public
    onlyDeployer
    notNullAddress(newFraudChallenge)
    notSameAddresses(newFraudChallenge, fraudChallenge)
    {
        // Set new fraud challenge
        FraudChallenge oldFraudChallenge = fraudChallenge;
        fraudChallenge = newFraudChallenge;

        // Emit event
        emit SetFraudChallengeEvent(oldFraudChallenge, newFraudChallenge);
    }

    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier fraudChallengeInitialized() {
        require(fraudChallenge != address(0));
        _;
    }
}
