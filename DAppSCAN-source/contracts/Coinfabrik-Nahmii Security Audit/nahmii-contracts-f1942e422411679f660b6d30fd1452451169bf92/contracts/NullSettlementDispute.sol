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
import {Configurable} from "./Configurable.sol";
import {Validatable} from "./Validatable.sol";
import {SecurityBondable} from "./SecurityBondable.sol";
import {WalletLockable} from "./WalletLockable.sol";
import {FraudChallengable} from "./FraudChallengable.sol";
import {CancelOrdersChallengable} from "./CancelOrdersChallengable.sol";
import {SafeMathIntLib} from "./SafeMathIntLib.sol";
import {SafeMathUintLib} from "./SafeMathUintLib.sol";
import {MonetaryTypesLib} from "./MonetaryTypesLib.sol";
import {NahmiiTypesLib} from "./NahmiiTypesLib.sol";
import {SettlementTypesLib} from "./SettlementTypesLib.sol";
import {CancelOrdersChallenge} from "./CancelOrdersChallenge.sol";
import {NullSettlementChallenge} from "./NullSettlementChallenge.sol";

/**
 * @title NullSettlementDispute
 * @notice The workhorse of null settlement challenges, utilized by NullSettlementChallenge
 */
contract NullSettlementDispute is Ownable, Configurable, Validatable, SecurityBondable, WalletLockable,
FraudChallengable, CancelOrdersChallengable {
    using SafeMathIntLib for int256;
    using SafeMathUintLib for uint256;

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    NullSettlementChallenge public nullSettlementChallenge;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetNullSettlementChallengeEvent(NullSettlementChallenge oldNullSettlementChallenge,
        NullSettlementChallenge newNullSettlementChallenge);
    event ChallengeByOrderEvent(address wallet, uint256 nonce,
        bytes32 candidateHash, address challenger);
    event ChallengeByTradeEvent(address wallet, uint256 nonce,
        bytes32 candidateHash, address challenger);
    event ChallengeByPaymentEvent(address wallet, uint256 nonce,
        bytes32 candidateHash, address challenger);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    /// @notice Set the settlement challenge contract
    /// @param newNullSettlementChallenge The (address of) NullSettlementChallenge contract instance
    function setNullSettlementChallenge(NullSettlementChallenge newNullSettlementChallenge) public
    onlyDeployer
    notNullAddress(newNullSettlementChallenge)
    {
        NullSettlementChallenge oldNullSettlementChallenge = nullSettlementChallenge;
        nullSettlementChallenge = newNullSettlementChallenge;
        emit SetNullSettlementChallengeEvent(oldNullSettlementChallenge, nullSettlementChallenge);
    }

    /// @notice Challenge the settlement by providing order candidate
    /// @param order The order candidate that challenges
    /// @param challenger The address of the challenger
    /// @dev If (candidate) order has buy intention consider _conjugate_ currency and amount, else
    /// if (candidate) order has sell intention consider _intended_ currency and amount
    function challengeByOrder(NahmiiTypesLib.Order order, address challenger)
    public
    onlyNullSettlementChallenge
    onlySealedOrder(order)
    {
        // Require that order candidate is not labelled fraudulent or cancelled
        require(!fraudChallenge.isFraudulentOrderHash(order.seals.operator.hash));
        require(!cancelOrdersChallenge.isOrderCancelled(order.wallet, order.seals.operator.hash));

        // Buy order -> Conjugate currency and amount
        // Sell order -> Intended currency and amount
        (int256 transferAmount, MonetaryTypesLib.Currency memory currency) =
        (NahmiiTypesLib.Intention.Sell == order.placement.intention ?
        (order.placement.amount, order.placement.currencies.intended) :
    (order.placement.amount.div(order.placement.rate), order.placement.currencies.conjugate));

        // Require that proposal has not expired
        require(!nullSettlementChallenge.hasProposalExpired(order.wallet, currency.ct, currency.id));

        // Require that proposal has not been disqualified already
        require(SettlementTypesLib.Status.Disqualified != nullSettlementChallenge.proposalStatus(
            order.wallet, currency.ct, currency.id
        ));

        // Require that order's block number is not earlier than proposal's block number
        require(order.blockNumber >= nullSettlementChallenge.proposalBlockNumber(
            order.wallet, currency.ct, currency.id
        ));

        // Require that transfer amount is strictly greater than the proposal's target balance amount
        // for this order to be a valid challenge candidate
        require(transferAmount > nullSettlementChallenge.proposalTargetBalanceAmount(
            order.wallet, currency.ct, currency.id
        ));

        // Update proposal status
        nullSettlementChallenge.setProposalStatus(
            order.wallet, currency.ct, currency.id, SettlementTypesLib.Status.Disqualified
        );

        // Lock wallet
        nullSettlementChallenge.lockWallet(order.wallet);

        // Add disqualification
        nullSettlementChallenge.addDisqualification(
            order.wallet, currency.ct, currency.id, order.seals.operator.hash,
            SettlementTypesLib.CandidateType.Order, challenger
        );

        // Slash wallet's balances or reward challenger by stake fraction
        if (nullSettlementChallenge.proposalBalanceReward(order.wallet, currency.ct, currency.id))
            walletLocker.lockFungibleByProxy(order.wallet, challenger, transferAmount, currency.ct, currency.id);
        else
            securityBond.reward(challenger, configuration.operatorSettlementStakeFraction(), 0);

        // Emit event
        emit ChallengeByOrderEvent(
            order.wallet,
            nullSettlementChallenge.proposalNonce(order.wallet, currency.ct, currency.id),
            nullSettlementChallenge.disqualificationCandidateHash(order.wallet, currency.ct, currency.id),
            challenger
        );
    }

    /// @notice Challenge the settlement by providing trade candidate
    /// @param wallet The wallet whose settlement is being challenged
    /// @param trade The trade candidate that challenges
    /// @param challenger The address of the challenger
    /// @dev If wallet is buyer in (candidate) trade consider single _conjugate_ transfer in (candidate) trade. Else
    /// if wallet is seller in (candidate) trade consider single _intended_ transfer in (candidate) trade
    function challengeByTrade(address wallet, NahmiiTypesLib.Trade trade, address challenger)
    public
    onlyNullSettlementChallenge
    onlySealedTrade(trade)
    onlyTradeParty(trade, wallet)
    {
        // Require that trade candidate is not labelled fraudulent
        require(!fraudChallenge.isFraudulentTradeHash(trade.seal.hash));

        // Require that wallet's order in trade is not labelled fraudulent or cancelled
        bytes32 orderHash = (trade.buyer.wallet == wallet ?
        trade.buyer.order.hashes.operator :
        trade.seller.order.hashes.operator);
        require(!fraudChallenge.isFraudulentOrderHash(orderHash));
        require(!cancelOrdersChallenge.isOrderCancelled(wallet, orderHash));

        // Get the relevant currency
        // Wallet is buyer in (candidate) trade -> Conjugate transfer and currency
        // Wallet is seller in (candidate) trade -> Intended transfer and currency
        (int256 transferAmount, MonetaryTypesLib.Currency memory currency) = (
        validator.isTradeBuyer(trade, wallet) ?
        (trade.transfers.conjugate.single.abs(), trade.currencies.conjugate) :
    (trade.transfers.intended.single.abs(), trade.currencies.intended)
        );

        // Require that proposal has not expired
        require(!nullSettlementChallenge.hasProposalExpired(wallet, currency.ct, currency.id));

        // Require that proposal has not been disqualified already
        require(SettlementTypesLib.Status.Disqualified != nullSettlementChallenge.proposalStatus(
            wallet, currency.ct, currency.id
        ));

        // Require that trade's block number is not earlier than proposal's block number
        require(trade.blockNumber >= nullSettlementChallenge.proposalBlockNumber(
            wallet, currency.ct, currency.id
        ));

        // Require that transfer amount is strictly greater than the proposal's target balance amount
        // for this trade to be a valid challenge candidate
        require(transferAmount > nullSettlementChallenge.proposalTargetBalanceAmount(
            wallet, currency.ct, currency.id
        ));

        // Update proposal status
        nullSettlementChallenge.setProposalStatus(
            wallet, currency.ct, currency.id, SettlementTypesLib.Status.Disqualified
        );

        // Lock wallet
        nullSettlementChallenge.lockWallet(wallet);

        // Add disqualification
        nullSettlementChallenge.addDisqualification(
            wallet, currency.ct, currency.id, trade.seal.hash,
            SettlementTypesLib.CandidateType.Trade, challenger
        );

        // Slash wallet's balances or reward challenger by stake fraction
        if (nullSettlementChallenge.proposalBalanceReward(wallet, currency.ct, currency.id))
            walletLocker.lockFungibleByProxy(wallet, challenger, transferAmount, currency.ct, currency.id);
        else
            securityBond.reward(challenger, configuration.operatorSettlementStakeFraction(), 0);

        // Emit event
        emit ChallengeByTradeEvent(
            wallet,
            nullSettlementChallenge.proposalNonce(wallet, currency.ct, currency.id),
            nullSettlementChallenge.disqualificationCandidateHash(wallet, currency.ct, currency.id),
            challenger
        );
    }

    /// @notice Challenge the settlement by providing payment candidate
    /// @dev This challenges the payment sender's side of things
    /// @param wallet The wallet whose settlement is being challenged
    /// @param payment The payment candidate that challenges
    /// @param challenger The address of the challenger
    function challengeByPayment(address wallet, NahmiiTypesLib.Payment payment, address challenger)
    public
    onlyNullSettlementChallenge
    onlySealedPayment(payment)
    onlyPaymentParty(payment, wallet)
    {
        // Require that payment candidate is not labelled fraudulent
        require(!fraudChallenge.isFraudulentPaymentHash(payment.seals.operator.hash));

        // Require that proposal has not expired
        require(!nullSettlementChallenge.hasProposalExpired(wallet, payment.currency.ct, payment.currency.id));

        // Require that proposal has not been disqualified already
        require(SettlementTypesLib.Status.Disqualified != nullSettlementChallenge.proposalStatus(
            wallet, payment.currency.ct, payment.currency.id
        ));

        // Require that payment's block number is not earlier than proposal's block number
        require(payment.blockNumber >= nullSettlementChallenge.proposalBlockNumber(
            wallet, payment.currency.ct, payment.currency.id
        ));

        // Require that transfer amount is strictly greater than the proposal's target balance amount
        // for this payment to be a valid challenge candidate
        require(payment.transfers.single.abs() > nullSettlementChallenge.proposalTargetBalanceAmount(
            wallet, payment.currency.ct, payment.currency.id
        ));

        // Update proposal status
        nullSettlementChallenge.setProposalStatus(
            wallet, payment.currency.ct, payment.currency.id, SettlementTypesLib.Status.Disqualified
        );

        // Lock wallet
        nullSettlementChallenge.lockWallet(wallet);

        // Add disqualification
        nullSettlementChallenge.addDisqualification(
            wallet, payment.currency.ct, payment.currency.id, payment.seals.operator.hash,
            SettlementTypesLib.CandidateType.Payment, challenger
        );

        // Slash wallet's balances or reward challenger by stake fraction
        if (nullSettlementChallenge.proposalBalanceReward(wallet, payment.currency.ct, payment.currency.id))
            walletLocker.lockFungibleByProxy(wallet, challenger, payment.transfers.single.abs(), payment.currency.ct, payment.currency.id);
        else
            securityBond.reward(challenger, configuration.operatorSettlementStakeFraction(), 0);

        // Emit event
        emit ChallengeByPaymentEvent(
            wallet,
            nullSettlementChallenge.proposalNonce(wallet, payment.currency.ct, payment.currency.id),
            nullSettlementChallenge.disqualificationCandidateHash(wallet, payment.currency.ct, payment.currency.id),
            challenger
        );
    }

    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier onlyNullSettlementChallenge() {
        require(msg.sender == address(nullSettlementChallenge));
        _;
    }
}