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
 * @title FraudChallengeBySuccessivePayments
 * @notice Where driips are challenged wrt fraud by mismatch in successive payments
 */
contract FraudChallengeBySuccessivePayments is Ownable, FraudChallengable, Challenge, Validatable,
SecurityBondable, WalletLockable {
    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event ChallengeBySuccessivePaymentsEvent(bytes32 firstPaymentHash,
        bytes32 lastPaymentHash, address challenger, address lockedWallet);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Submit two payment candidates in continuous Fraud Challenge (FC)
    /// to be tested for succession differences
    /// @param firstPayment Reference payment
    /// @param lastPayment Fraudulent payment candidate
    /// @param wallet The address of the concerned wallet
    function challenge(
        NahmiiTypesLib.Payment firstPayment,
        NahmiiTypesLib.Payment lastPayment,
        address wallet
    )
    public
    onlyOperationalModeNormal
    onlySealedPayment(firstPayment)
    onlySealedPayment(lastPayment)
    {
        require(validator.isPaymentParty(firstPayment, wallet));
        require(validator.isPaymentParty(lastPayment, wallet));
        require(firstPayment.currency.ct == lastPayment.currency.ct && firstPayment.currency.id == lastPayment.currency.id);

        NahmiiTypesLib.PaymentPartyRole firstPaymentPartyRole = (wallet == firstPayment.sender.wallet ? NahmiiTypesLib.PaymentPartyRole.Sender : NahmiiTypesLib.PaymentPartyRole.Recipient);
        NahmiiTypesLib.PaymentPartyRole lastPaymentPartyRole = (wallet == lastPayment.sender.wallet ? NahmiiTypesLib.PaymentPartyRole.Sender : NahmiiTypesLib.PaymentPartyRole.Recipient);

        require(validator.isSuccessivePaymentsPartyNonces(firstPayment, firstPaymentPartyRole, lastPayment, lastPaymentPartyRole));

        require(
            !validator.isGenuineSuccessivePaymentsBalances(firstPayment, firstPaymentPartyRole, lastPayment, lastPaymentPartyRole) ||
        !validator.isGenuineSuccessivePaymentsTotalFees(firstPayment, lastPayment)
        );

        configuration.setOperationalModeExit();
        fraudChallenge.addFraudulentPaymentHash(lastPayment.seals.operator.hash);

        // Reward stake fraction
        securityBond.reward(msg.sender, configuration.fraudStakeFraction(), 0);

//        walletLocker.lockByProxy(wallet, msg.sender);

        emit ChallengeBySuccessivePaymentsEvent(
            firstPayment.seals.operator.hash, lastPayment.seals.operator.hash, msg.sender, wallet
        );
    }
}