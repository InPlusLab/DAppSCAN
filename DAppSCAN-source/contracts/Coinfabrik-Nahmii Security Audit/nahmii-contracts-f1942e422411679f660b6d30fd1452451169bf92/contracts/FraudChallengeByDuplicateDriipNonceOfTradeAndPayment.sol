/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {Ownable} from "./Ownable.sol";
import {FraudChallengable} from "./FraudChallengable.sol";
import {Challenge} from "./Challenge.sol";
import {Validatable} from "./Validatable.sol";
import {SecurityBondable} from "./SecurityBondable.sol";
import {NahmiiTypesLib} from "./NahmiiTypesLib.sol";

/**
 * @title FraudChallengeByDuplicateDriipNonceOfTradeAndPayment
 * @notice Where driips are challenged wrt fraud by duplicate drip nonce of trade and payment
 */
contract FraudChallengeByDuplicateDriipNonceOfTradeAndPayment is Ownable, FraudChallengable, Challenge, Validatable,
SecurityBondable {
    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event ChallengeByDuplicateDriipNonceOfTradeAndPaymentEvent(bytes32 tradeHash,
        bytes32 paymentHash, address challenger);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Submit one trade candidate and one payment candidate in continuous Fraud
    /// Challenge (FC) to be tested for duplicate driip nonce
    /// @param trade Trade with duplicate driip nonce
    /// @param payment Payment with duplicate driip nonce
    function challenge(
        NahmiiTypesLib.Trade trade,
        NahmiiTypesLib.Payment payment
    )
    public
    onlyOperationalModeNormal
    onlySealedTrade(trade)
    onlySealedPayment(payment)
    {
        require(trade.nonce == payment.nonce);

        configuration.setOperationalModeExit();
        fraudChallenge.addFraudulentTradeHash(trade.seal.hash);
        fraudChallenge.addFraudulentPaymentHash(payment.seals.operator.hash);

        // Reward stake fraction
        securityBond.reward(msg.sender, configuration.fraudStakeFraction(), 0);

        emit ChallengeByDuplicateDriipNonceOfTradeAndPaymentEvent(
            trade.seal.hash, payment.seals.operator.hash, msg.sender
        );
    }
}