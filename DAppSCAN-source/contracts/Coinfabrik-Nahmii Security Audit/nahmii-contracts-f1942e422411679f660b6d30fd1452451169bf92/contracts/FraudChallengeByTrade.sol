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
 * @title FraudChallengeByTrade
 * @notice Where driips are challenged wrt fraud by mismatch in single trade property values
 */
contract FraudChallengeByTrade is Ownable, FraudChallengable, Challenge, Validatable,
SecurityBondable, WalletLockable {
    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event ChallengeByTradeEvent(bytes32 tradeHash, address challenger, address lockedWallet);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Submit a trade candidate in continuous Fraud Challenge (FC)
    /// @param trade Fraudulent trade candidate
    function challenge(NahmiiTypesLib.Trade trade) public
    onlyOperationalModeNormal
    onlySealedTrade(trade)
    {
        // Genuineness affected by buyer
        bool genuineBuyerAndFee = validator.isTradeIntendedCurrencyNonFungible(trade) ?
        validator.isGenuineTradeBuyerOfNonFungible(trade) && validator.isGenuineTradeBuyerFeeOfNonFungible(trade) :
        validator.isGenuineTradeBuyerOfFungible(trade) && validator.isGenuineTradeBuyerFeeOfFungible(trade);

        // Genuineness affected by seller
        bool genuineSellerAndFee = validator.isTradeConjugateCurrencyNonFungible(trade) ?
        validator.isGenuineTradeSellerOfNonFungible(trade) && validator.isGenuineTradeSellerFeeOfNonFungible(trade) :
        validator.isGenuineTradeSellerOfFungible(trade) && validator.isGenuineTradeSellerFeeOfFungible(trade);

        require(!genuineBuyerAndFee || !genuineSellerAndFee);

        configuration.setOperationalModeExit();
        fraudChallenge.addFraudulentTradeHash(trade.seal.hash);

        // Reward stake fraction
        securityBond.reward(msg.sender, configuration.fraudStakeFraction(), 0);

        address lockedWallet;
        if (!genuineBuyerAndFee)
            lockedWallet = trade.buyer.wallet;
        if (!genuineSellerAndFee)
            lockedWallet = trade.seller.wallet;
//        if (address(0) != lockedWallet)
//            walletLocker.lockByProxy(lockedWallet, msg.sender);

        emit ChallengeByTradeEvent(trade.seal.hash, msg.sender, lockedWallet);
    }
}