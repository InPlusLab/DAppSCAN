/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Ownable} from "./Ownable.sol";
import {CancelOrdersChallenge} from "./CancelOrdersChallenge.sol";

/**
 * @title CancelOrdersChallengable
 * @notice An ownable that has a cancel orders challenge property
 */
contract CancelOrdersChallengable is Ownable {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    CancelOrdersChallenge public cancelOrdersChallenge;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetCancelOrdersChallengeEvent(CancelOrdersChallenge oldCancelOrdersChallenge,
        CancelOrdersChallenge newCancelOrdersChallenge);

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Set the cancel orders challenge contract
    /// @param newCancelOrdersChallenge The (address of) CancelOrdersChallenge contract instance
    function setCancelOrdersChallenge(CancelOrdersChallenge newCancelOrdersChallenge)
    public
    onlyDeployer
    notNullAddress(newCancelOrdersChallenge)
    notSameAddresses(newCancelOrdersChallenge, cancelOrdersChallenge)
    {
        // Set new cancel orders challenge
        CancelOrdersChallenge oldCancelOrdersChallenge = cancelOrdersChallenge;
        cancelOrdersChallenge = newCancelOrdersChallenge;

        // Emit event
        emit SetCancelOrdersChallengeEvent(oldCancelOrdersChallenge, newCancelOrdersChallenge);
    }

    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier cancelOrdersChallengeInitialized() {
        require(cancelOrdersChallenge != address(0));
        _;
    }
}
