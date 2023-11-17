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
import {WalletLockable} from "./WalletLockable.sol";
import {NahmiiTypesLib} from "./NahmiiTypesLib.sol";

/**
 * @title FraudChallengeByPayment
 * @notice Where driips are challenged wrt fraud by mismatch in single trade property values
 */
contract FraudChallengeByPayment is Ownable, FraudChallengable, Challenge, Validatable,
SecurityBondable, WalletLockable {
    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event ChallengeByPaymentEvent(bytes32 paymentHash, address challenger,
        address lockedWallet);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Submit a payment candidate in continuous Fraud Challenge (FC)
    /// @param payment Fraudulent payment candidate
    function challenge(NahmiiTypesLib.Payment payment)
    public
    onlyOperationalModeNormal
    onlyOperatorSealedPayment(payment)
    {
        require(validator.isGenuinePaymentWalletHash(payment));

        // Genuineness affected by wallet not having signed the payment
        bool genuineWalletSignature = validator.isGenuineWalletSignature(
            payment.seals.wallet.hash, payment.seals.wallet.signature, payment.sender.wallet
        );

        // Genuineness affected by sender and recipient
        bool genuineSenderAndFee;
        bool genuineRecipient;
        if (validator.isPaymentCurrencyNonFungible(payment)) {
            genuineSenderAndFee = validator.isGenuinePaymentSenderOfNonFungible(payment)
            && validator.isGenuinePaymentFeeOfNonFungible(payment);

            genuineRecipient = validator.isGenuinePaymentRecipientOfNonFungible(payment);
        } else {
            genuineSenderAndFee = validator.isGenuinePaymentSenderOfFungible(payment)
            && validator.isGenuinePaymentFeeOfFungible(payment);

            genuineRecipient = validator.isGenuinePaymentRecipientOfFungible(payment);
        }

        require(!genuineWalletSignature || !genuineSenderAndFee || !genuineRecipient);

        configuration.setOperationalModeExit();
        fraudChallenge.addFraudulentPaymentHash(payment.seals.operator.hash);

        // Reward stake fraction
        securityBond.reward(msg.sender, configuration.fraudStakeFraction(), 0);

        address lockedWallet;
        if (!genuineSenderAndFee)
            lockedWallet = payment.sender.wallet;
        if (!genuineRecipient)
            lockedWallet = payment.recipient.wallet;
//        if (address(0) != lockedWallet)
//            walletLocker.lockByProxy(lockedWallet, msg.sender);

        emit ChallengeByPaymentEvent(payment.seals.operator.hash, msg.sender, lockedWallet);
    }
}