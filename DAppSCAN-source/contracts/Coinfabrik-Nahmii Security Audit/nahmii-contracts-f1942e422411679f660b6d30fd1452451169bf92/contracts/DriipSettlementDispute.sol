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
import {DriipSettlementChallenge} from "./DriipSettlementChallenge.sol";

/**
 * @title DriipSettlementDispute
 * @notice The workhorse of driip settlement challenges, utilized by DriipSettlementChallenge
 */
contract DriipSettlementDispute is Ownable, Configurable, Validatable, SecurityBondable, WalletLockable, FraudChallengable,
CancelOrdersChallengable {
    using SafeMathIntLib for int256;
    using SafeMathUintLib for uint256;

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    DriipSettlementChallenge public driipSettlementChallenge;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetDriipSettlementChallengeEvent(DriipSettlementChallenge oldDriipSettlementChallenge,
        DriipSettlementChallenge newDriipSettlementChallenge);
    event ChallengeByOrderEvent(address wallet, uint256 nonce,
        bytes32 driipHash, NahmiiTypesLib.DriipType driipType,
        bytes32 candidateHash, address challenger);
    event UnchallengeOrderCandidateByTradeEvent(address wallet, uint256 nonce,
        bytes32 driipHash, NahmiiTypesLib.DriipType driipType,
        bytes32 challengeCandidateHash, address challenger,
        bytes32 unchallengeCandidateHash, address unchallenger);
    event ChallengeByTradeEvent(address wallet, uint256 nonce,
        bytes32 driipHash, NahmiiTypesLib.DriipType driipType,
        bytes32 candidateHash, address challenger);
    event ChallengeByPaymentEvent(address wallet, uint256 nonce,
        bytes32 driipHash, NahmiiTypesLib.DriipType driipType,
        bytes32 candidateHash, address challenger);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    /// @notice Set the driip settlement challenge contract
    /// @param newDriipSettlementChallenge The (address of) DriipSettlementChallenge contract instance
    function setDriipSettlementChallenge(DriipSettlementChallenge newDriipSettlementChallenge) public
    onlyDeployer
    notNullAddress(newDriipSettlementChallenge)
    {
        DriipSettlementChallenge oldDriipSettlementChallenge = driipSettlementChallenge;
        driipSettlementChallenge = newDriipSettlementChallenge;
        emit SetDriipSettlementChallengeEvent(oldDriipSettlementChallenge, driipSettlementChallenge);
    }

    /// @notice Challenge the driip settlement by providing order candidate
    /// @param order The order candidate that challenges the challenged driip
    /// @param challenger The address of the challenger
    /// @dev If (candidate) order has buy intention consider _conjugate_ currency and amount, else
    /// if (candidate) order has sell intention consider _intended_ currency and amount
    function challengeByOrder(NahmiiTypesLib.Order order, address challenger) public
    onlyDriipSettlementChallenge
    onlySealedOrder(order)
    {
        // Require that candidate order is not labelled fraudulent or cancelled
        require(!fraudChallenge.isFraudulentOrderHash(order.seals.operator.hash));
        require(!cancelOrdersChallenge.isOrderCancelled(order.wallet, order.seals.operator.hash));

        // Get the relevant currency
        // Buy order -> Conjugate transfer and currency
        // Sell order -> Intended transfer and currency
        (int256 transferAmount, MonetaryTypesLib.Currency memory currency) = (
        NahmiiTypesLib.Intention.Sell == order.placement.intention ?
        (order.placement.amount, order.placement.currencies.intended) :
    (order.placement.amount.div(order.placement.rate), order.placement.currencies.conjugate)
        );

        // Require that proposal has not expired
        require(!driipSettlementChallenge.hasProposalExpired(order.wallet, currency.ct, currency.id));

        // Require that proposal has not been disqualified already
        require(SettlementTypesLib.Status.Disqualified != driipSettlementChallenge.proposalStatus(
            order.wallet, currency.ct, currency.id
        ));

        // Require that order's block number is not earlier than proposal's block number
        require(order.blockNumber >= driipSettlementChallenge.proposalBlockNumber(
            order.wallet, currency.ct, currency.id
        ));

        // Require that transfer amount is strictly greater than the proposal's target balance amount
        // for this order to be a valid challenge candidate
        require(transferAmount > driipSettlementChallenge.proposalTargetBalanceAmount(
            order.wallet, currency.ct, currency.id
        ));

        // Update proposal
        driipSettlementChallenge.setProposalExpirationTime(
            order.wallet, currency.ct, currency.id, block.timestamp.add(configuration.settlementChallengeTimeout())
        );
        driipSettlementChallenge.setProposalStatus(
            order.wallet, currency.ct, currency.id, SettlementTypesLib.Status.Disqualified
        );

        // Lock wallet
        driipSettlementChallenge.lockWallet(order.wallet);

        // Add disqualification
        driipSettlementChallenge.addDisqualification(
            order.wallet, currency.ct, currency.id, order.seals.operator.hash,
            SettlementTypesLib.CandidateType.Order, challenger
        );

        // Slash wallet's balances or reward challenger by stake fraction
        if (driipSettlementChallenge.proposalBalanceReward(order.wallet, currency.ct, currency.id))
            walletLocker.lockFungibleByProxy(order.wallet, challenger, transferAmount, currency.ct, currency.id);
        else
            securityBond.reward(challenger, configuration.operatorSettlementStakeFraction(),
                configuration.settlementChallengeTimeout());

        // Emit event
        emit ChallengeByOrderEvent(
            order.wallet,
            driipSettlementChallenge.proposalNonce(order.wallet, currency.ct, currency.id),
            driipSettlementChallenge.proposalDriipHash(order.wallet, currency.ct, currency.id),
            driipSettlementChallenge.proposalDriipType(order.wallet, currency.ct, currency.id),
            driipSettlementChallenge.disqualificationCandidateHash(order.wallet, currency.ct, currency.id),
            challenger
        );
    }

    /// @notice Unchallenge driip settlement by providing trade that shows that challenge order candidate has been filled
    /// @param order The order candidate that challenged driip
    /// @param trade The trade in which order has been filled
    /// @param unchallenger The address of the unchallenger
    function unchallengeOrderCandidateByTrade(NahmiiTypesLib.Order order, NahmiiTypesLib.Trade trade, address unchallenger)
    public
    onlyDriipSettlementChallenge
    onlySealedOrder(order)
    onlySealedTrade(trade)
    onlyTradeParty(trade, order.wallet)
    {
        require(validator.isTradeOrder(trade, order));

        // Get the relevant currency
        // Buy order -> Conjugate currency
        // Sell order -> Intended currency
        MonetaryTypesLib.Currency memory currency = (
        NahmiiTypesLib.Intention.Sell == order.placement.intention ?
        order.placement.currencies.intended :
        order.placement.currencies.conjugate
        );

        // Require that proposal has not expired
        require(!driipSettlementChallenge.hasProposalExpired(order.wallet, currency.ct, currency.id));

        // Require that proposal has been disqualified
        require(SettlementTypesLib.Status.Disqualified == driipSettlementChallenge.proposalStatus(
            order.wallet, currency.ct, currency.id
        ));

        // Require that candidate type is order
        require(SettlementTypesLib.CandidateType.Order == driipSettlementChallenge.disqualificationCandidateType(
            order.wallet, currency.ct, currency.id
        ));

        // Require that trade is not labelled fraudulent
        require(!fraudChallenge.isFraudulentTradeHash(trade.seal.hash));

        // Require that trade candidate's order is not labelled fraudulent
        require(!fraudChallenge.isFraudulentOrderHash(
            validator.isTradeBuyer(trade, order.wallet) ?
            trade.buyer.order.hashes.operator :
            trade.seller.order.hashes.operator
        ));

        bytes32 candidateHash = driipSettlementChallenge.disqualificationCandidateHash(
            order.wallet, currency.ct, currency.id
        );

        // Require that the order's hash equals the candidate order's hash
        require(order.seals.operator.hash == candidateHash);

        // Order wallet is buyer -> require candidate order's hash to match buyer's order hash
        // Order wallet is seller -> require candidate order's hash to match seller's order hash
        require(candidateHash == (
        validator.isTradeBuyer(trade, order.wallet) ?
        trade.buyer.order.hashes.operator :
        trade.seller.order.hashes.operator
        ));

        // Update proposal
        driipSettlementChallenge.setProposalStatus(
            order.wallet, currency.ct, currency.id, SettlementTypesLib.Status.Qualified
        );

        // Get challenger
        address challenger = driipSettlementChallenge.disqualificationChallenger(order.wallet, currency.ct, currency.id);

        // Remove disqualification
        driipSettlementChallenge.removeDisqualification(order.wallet, currency.ct, currency.id);

        // Unlock wallet's balances or deprive challenger
        if (driipSettlementChallenge.proposalBalanceReward(order.wallet, currency.ct, currency.id))
            walletLocker.unlockFungibleByProxy(order.wallet, challenger, currency.ct, currency.id);
        else
            securityBond.deprive(challenger);

        // Reward unchallenger
        securityBond.reward(unchallenger, configuration.walletSettlementStakeFraction(), 0);

        // Emit event
        emit UnchallengeOrderCandidateByTradeEvent(
            order.wallet,
            driipSettlementChallenge.proposalNonce(order.wallet, currency.ct, currency.id),
            driipSettlementChallenge.proposalDriipHash(order.wallet, currency.ct, currency.id),
            driipSettlementChallenge.proposalDriipType(order.wallet, currency.ct, currency.id),
            candidateHash, challenger,
            trade.seal.hash, unchallenger
        );
    }

    /// @notice Challenge the driip settlement by providing trade candidate
    /// @param wallet The wallet whose driip settlement is being challenged
    /// @param trade The trade candidate that challenges the challenged driip
    /// @param challenger The address of the challenger
    /// @dev If wallet is buyer in (candidate) trade consider single _conjugate_ transfer in (candidate) trade. Else
    /// if wallet is seller in (candidate) trade consider single _intended_ transfer in (candidate) trade
    function challengeByTrade(address wallet, NahmiiTypesLib.Trade trade, address challenger)
    public
    onlyDriipSettlementChallenge
    onlySealedTrade(trade)
    onlyTradeParty(trade, wallet)
    {
        // Require that trade candidate is not labelled fraudulent
        require(!fraudChallenge.isFraudulentTradeHash(trade.seal.hash));

        // Require that wallet's order in trade is not labelled fraudulent or cancelled
        bytes32 orderHash = (validator.isTradeBuyer(trade, wallet) ?
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
        require(!driipSettlementChallenge.hasProposalExpired(wallet, currency.ct, currency.id));

        // Require that proposal has not been disqualified already
        require(SettlementTypesLib.Status.Disqualified != driipSettlementChallenge.proposalStatus(
            wallet, currency.ct, currency.id
        ));

        // Require that trade's block number is not earlier than proposal's block number
        require(trade.blockNumber >= driipSettlementChallenge.proposalBlockNumber(
            wallet, currency.ct, currency.id
        ));

        // Require that transfer amount is strictly greater than the proposal's target balance amount
        // for this trade to be a valid challenge candidate
        require(transferAmount > driipSettlementChallenge.proposalTargetBalanceAmount(
            wallet, currency.ct, currency.id
        ));

        // Update proposal status
        driipSettlementChallenge.setProposalStatus(
            wallet, currency.ct, currency.id, SettlementTypesLib.Status.Disqualified
        );

        // Lock wallet
        driipSettlementChallenge.lockWallet(wallet);

        // Add disqualification
        driipSettlementChallenge.addDisqualification(
            wallet, currency.ct, currency.id, trade.seal.hash,
            SettlementTypesLib.CandidateType.Trade, challenger
        );

        // Slash wallet's balances or reward challenger by stake fraction
        if (driipSettlementChallenge.proposalBalanceReward(wallet, currency.ct, currency.id))
            walletLocker.lockFungibleByProxy(wallet, challenger, transferAmount, currency.ct, currency.id);
        else
            securityBond.reward(challenger, configuration.operatorSettlementStakeFraction(), 0);

        // Emit event
        emit ChallengeByTradeEvent(
            wallet,
            driipSettlementChallenge.proposalNonce(wallet, currency.ct, currency.id),
            driipSettlementChallenge.proposalDriipHash(wallet, currency.ct, currency.id),
            driipSettlementChallenge.proposalDriipType(wallet, currency.ct, currency.id),
            driipSettlementChallenge.disqualificationCandidateHash(wallet, currency.ct, currency.id),
            challenger
        );
    }

    /// @notice Challenge the driip settlement by providing payment candidate
    /// @dev This challenges the payment sender's side of things
    /// @param wallet The concerned party
    /// @param payment The payment candidate that challenges the challenged driip
    /// @param challenger The address of the challenger
    function challengeByPayment(address wallet, NahmiiTypesLib.Payment payment, address challenger)
    public
    onlyDriipSettlementChallenge
    onlySealedPayment(payment)
    onlyPaymentParty(payment, wallet)
    {
        // Require that payment candidate is not labelled fraudulent
        require(!fraudChallenge.isFraudulentPaymentHash(payment.seals.operator.hash));

        // Require that proposal has not expired
        require(!driipSettlementChallenge.hasProposalExpired(wallet, payment.currency.ct, payment.currency.id));

        // Require that proposal has not been disqualified already
        require(SettlementTypesLib.Status.Disqualified != driipSettlementChallenge.proposalStatus(
            wallet, payment.currency.ct, payment.currency.id
        ));

        // Require that payment's block number is not earlier than proposal's block number
        require(payment.blockNumber >= driipSettlementChallenge.proposalBlockNumber(
            wallet, payment.currency.ct, payment.currency.id
        ));

        // Get the payment's signed transfer amount, where positive transfer is always in direction from sender to recipient
        int256 transferAmount = validator.isPaymentSender(payment, wallet) ? payment.transfers.single : payment.transfers.single.mul(- 1);

        // Require that transfer amount is strictly greater than the proposal's target balance amount
        // for this payment to be a valid challenge candidate
        require(transferAmount > driipSettlementChallenge.proposalTargetBalanceAmount(
            wallet, payment.currency.ct, payment.currency.id
        ));

        // Update proposal status
        driipSettlementChallenge.setProposalStatus(
            wallet, payment.currency.ct, payment.currency.id, SettlementTypesLib.Status.Disqualified
        );

        // Lock wallet
        driipSettlementChallenge.lockWallet(wallet);

        // Add disqualification
        driipSettlementChallenge.addDisqualification(
            wallet, payment.currency.ct, payment.currency.id, payment.seals.operator.hash,
            SettlementTypesLib.CandidateType.Payment, challenger
        );

        // Slash wallet's balances or reward challenger by stake fraction
        if (driipSettlementChallenge.proposalBalanceReward(wallet, payment.currency.ct, payment.currency.id))
            walletLocker.lockFungibleByProxy(wallet, challenger, transferAmount.abs(), payment.currency.ct, payment.currency.id);
        else
            securityBond.reward(challenger, configuration.operatorSettlementStakeFraction(), 0);

        // Emit event
        emit ChallengeByPaymentEvent(
            wallet,
            driipSettlementChallenge.proposalNonce(wallet, payment.currency.ct, payment.currency.id),
            driipSettlementChallenge.proposalDriipHash(wallet, payment.currency.ct, payment.currency.id),
            driipSettlementChallenge.proposalDriipType(wallet, payment.currency.ct, payment.currency.id),
            driipSettlementChallenge.disqualificationCandidateHash(wallet, payment.currency.ct, payment.currency.id),
            challenger
        );
    }

    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier driipSettlementChallengeInitialized() {
        require(driipSettlementChallenge != address(0));
        _;
    }

    modifier onlyDriipSettlementChallenge() {
        require(msg.sender == address(driipSettlementChallenge));
        _;
    }
}