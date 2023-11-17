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
 * @title FraudChallengeByDuplicateDriipNonceOfPayments
 * @notice Where driips are challenged wrt fraud by duplicate drip nonce of payments
 */
contract FraudChallengeByDuplicateDriipNonceOfPayments is Ownable, FraudChallengable, Challenge, Validatable,
SecurityBondable {
    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event ChallengeByDuplicateDriipNonceOfPaymentsEvent(bytes32 paymentHash1,
        bytes32 paymentHash2, address challenger);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Submit two payment candidates in continuous Fraud Challenge (FC) to be tested for
    /// duplicate driip nonce
    /// @param payment1 First payment with duplicate driip nonce
    /// @param payment2 Second payment with duplicate driip nonce
    function challenge(
        NahmiiTypesLib.Payment payment1,
        NahmiiTypesLib.Payment payment2
    )
    public
    onlyOperationalModeNormal
    onlySealedPayment(payment1)
    onlySealedPayment(payment2)
    {
        require(payment1.seals.wallet.hash != payment2.seals.wallet.hash);
        require(payment1.nonce == payment2.nonce);

        configuration.setOperationalModeExit();
        fraudChallenge.addFraudulentPaymentHash(payment1.seals.operator.hash);
        fraudChallenge.addFraudulentPaymentHash(payment2.seals.operator.hash);

        // Reward stake fraction
        securityBond.reward(msg.sender, configuration.fraudStakeFraction(), 0);

        emit ChallengeByDuplicateDriipNonceOfPaymentsEvent(
            payment1.seals.operator.hash, payment2.seals.operator.hash, msg.sender
        );
    }
}