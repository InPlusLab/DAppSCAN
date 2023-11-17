/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {SafeMathIntLib} from "./SafeMathIntLib.sol";
import {SafeMathUintLib} from "./SafeMathUintLib.sol";
import {MonetaryTypesLib} from "./MonetaryTypesLib.sol";
import {NahmiiTypesLib} from "./NahmiiTypesLib.sol";
import {Configurable} from "./Configurable.sol";
import {Hashable} from "./Hashable.sol";
import {Ownable} from "./Ownable.sol";
import {SignerManageable} from "./SignerManageable.sol";
import {ConstantsLib} from "./ConstantsLib.sol";

/**
 * @title Validator
 * @notice An ownable that validates valuable types (order, trade, payment)
 */
contract Validator is Ownable, SignerManageable, Configurable, Hashable {
    using SafeMathIntLib for int256;
    using SafeMathUintLib for uint256;

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer, address signerManager) Ownable(deployer) SignerManageable(signerManager) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    // @dev Logics of this function only applies to FT
    function isGenuineTradeBuyerFeeOfFungible(NahmiiTypesLib.Trade trade)
    public
    view
    returns (bool)
    {
        int256 feePartsPer = ConstantsLib.PARTS_PER();
        int256 discountTier = int256(trade.buyer.rollingVolume);

        int256 feeAmount;
        if (NahmiiTypesLib.LiquidityRole.Maker == trade.buyer.liquidityRole) {
            feeAmount = trade.amount
            .mul(configuration.tradeMakerFee(trade.blockNumber, discountTier))
            .div(feePartsPer);

            if (1 > feeAmount)
                feeAmount = 1;

            return (trade.buyer.fees.single.amount == feeAmount);

        } else {// NahmiiTypesLib.LiquidityRole.Taker == trade.buyer.liquidityRole
            feeAmount = trade.amount
            .mul(configuration.tradeTakerFee(trade.blockNumber, discountTier))
            .div(feePartsPer);

            if (1 > feeAmount)
                feeAmount = 1;

            return (trade.buyer.fees.single.amount == feeAmount);
        }
    }

    // @dev Logics of this function only applies to FT
    function isGenuineTradeSellerFeeOfFungible(NahmiiTypesLib.Trade trade)
    public
    view
    returns (bool)
    {
        int256 feePartsPer = ConstantsLib.PARTS_PER();
        int256 discountTier = int256(trade.seller.rollingVolume);

        int256 feeAmount;
        if (NahmiiTypesLib.LiquidityRole.Maker == trade.seller.liquidityRole) {
            feeAmount = trade.amount
            .mul(configuration.tradeMakerFee(trade.blockNumber, discountTier))
            .div(trade.rate.mul(feePartsPer));

            if (1 > feeAmount)
                feeAmount = 1;

            return (trade.seller.fees.single.amount == feeAmount);

        } else {// NahmiiTypesLib.LiquidityRole.Taker == trade.seller.liquidityRole
            feeAmount = trade.amount
            .mul(configuration.tradeTakerFee(trade.blockNumber, discountTier))
            .div(trade.rate.mul(feePartsPer));

            if (1 > feeAmount)
                feeAmount = 1;

            return (trade.seller.fees.single.amount == feeAmount);
        }
    }

    // @dev Logics of this function only applies to NFT
    function isGenuineTradeBuyerFeeOfNonFungible(NahmiiTypesLib.Trade trade)
    public
    view
    returns (bool)
    {
        (address feeCurrencyCt, uint256 feeCurrencyId) = configuration.feeCurrency(
            trade.blockNumber, trade.currencies.intended.ct, trade.currencies.intended.id
        );

        return feeCurrencyCt == trade.buyer.fees.single.currency.ct
        && feeCurrencyId == trade.buyer.fees.single.currency.id;
    }

    // @dev Logics of this function only applies to NFT
    function isGenuineTradeSellerFeeOfNonFungible(NahmiiTypesLib.Trade trade)
    public
    view
    returns (bool)
    {
        (address feeCurrencyCt, uint256 feeCurrencyId) = configuration.feeCurrency(
            trade.blockNumber, trade.currencies.conjugate.ct, trade.currencies.conjugate.id
        );

        return feeCurrencyCt == trade.seller.fees.single.currency.ct
        && feeCurrencyId == trade.seller.fees.single.currency.id;
    }

    // @dev Logics of this function only applies to FT
    function isGenuineTradeBuyerOfFungible(NahmiiTypesLib.Trade trade)
    public
    view
    returns (bool)
    {
        return (trade.buyer.wallet != trade.seller.wallet)
        && (!signerManager.isSigner(trade.buyer.wallet))
        && (trade.buyer.balances.intended.current == trade.buyer.balances.intended.previous.add(trade.transfers.intended.single).sub(trade.buyer.fees.single.amount))
        && (trade.buyer.balances.conjugate.current == trade.buyer.balances.conjugate.previous.sub(trade.transfers.conjugate.single))
        && (trade.buyer.order.amount >= trade.buyer.order.residuals.current)
        && (trade.buyer.order.amount >= trade.buyer.order.residuals.previous)
        && (trade.buyer.order.residuals.previous >= trade.buyer.order.residuals.current);
    }

    // @dev Logics of this function only applies to FT
    function isGenuineTradeSellerOfFungible(NahmiiTypesLib.Trade trade)
    public
    view
    returns (bool)
    {
        return (trade.buyer.wallet != trade.seller.wallet)
        && (!signerManager.isSigner(trade.seller.wallet))
        && (trade.seller.balances.intended.current == trade.seller.balances.intended.previous.sub(trade.transfers.intended.single))
        && (trade.seller.balances.conjugate.current == trade.seller.balances.conjugate.previous.add(trade.transfers.conjugate.single).sub(trade.seller.fees.single.amount))
        && (trade.seller.order.amount >= trade.seller.order.residuals.current)
        && (trade.seller.order.amount >= trade.seller.order.residuals.previous)
        && (trade.seller.order.residuals.previous >= trade.seller.order.residuals.current);
    }

    // @dev Logics of this function only applies to NFT
    function isGenuineTradeBuyerOfNonFungible(NahmiiTypesLib.Trade trade)
    public
    view
    returns (bool)
    {
        return (trade.buyer.wallet != trade.seller.wallet)
        && (!signerManager.isSigner(trade.buyer.wallet));
    }

    // @dev Logics of this function only applies to NFT
    function isGenuineTradeSellerOfNonFungible(NahmiiTypesLib.Trade trade)
    public
    view
    returns (bool)
    {
        return (trade.buyer.wallet != trade.seller.wallet)
        && (!signerManager.isSigner(trade.seller.wallet));
    }

    function isGenuineOrderWalletHash(NahmiiTypesLib.Order order)
    public
    view
    returns (bool)
    {
        return hasher.hashOrderAsWallet(order) == order.seals.wallet.hash;
    }

    function isGenuineOrderOperatorHash(NahmiiTypesLib.Order order)
    public
    view
    returns (bool)
    {
        return hasher.hashOrderAsOperator(order) == order.seals.operator.hash;
    }

    function isGenuineOperatorSignature(bytes32 hash, NahmiiTypesLib.Signature signature)
    public
    view
    returns (bool)
    {
        return isSignedByRegisteredSigner(hash, signature.v, signature.r, signature.s);
    }

    function isGenuineWalletSignature(bytes32 hash, NahmiiTypesLib.Signature signature, address wallet)
    public
    pure
    returns (bool)
    {
        return isSignedBy(hash, signature.v, signature.r, signature.s, wallet);
    }

    function isGenuineOrderWalletSeal(NahmiiTypesLib.Order order)
    public
    view
    returns (bool)
    {
        return isGenuineOrderWalletHash(order)
        && isGenuineWalletSignature(order.seals.wallet.hash, order.seals.wallet.signature, order.wallet);
    }

    function isGenuineOrderOperatorSeal(NahmiiTypesLib.Order order)
    public
    view
    returns (bool)
    {
        return isGenuineOrderOperatorHash(order)
        && isGenuineOperatorSignature(order.seals.operator.hash, order.seals.operator.signature);
    }

    function isGenuineOrderSeals(NahmiiTypesLib.Order order)
    public
    view
    returns (bool)
    {
        return isGenuineOrderWalletSeal(order) && isGenuineOrderOperatorSeal(order);
    }

    function isGenuineTradeHash(NahmiiTypesLib.Trade trade)
    public
    view
    returns (bool)
    {
        return hasher.hashTrade(trade) == trade.seal.hash;
    }

    function isGenuineTradeSeal(NahmiiTypesLib.Trade trade)
    public
    view
    returns (bool)
    {
        return isGenuineTradeHash(trade)
        && isGenuineOperatorSignature(trade.seal.hash, trade.seal.signature);
    }

    function isGenuinePaymentWalletHash(NahmiiTypesLib.Payment payment)
    public
    view
    returns (bool)
    {
        return hasher.hashPaymentAsWallet(payment) == payment.seals.wallet.hash;
    }

    function isGenuinePaymentOperatorHash(NahmiiTypesLib.Payment payment)
    public
    view
    returns (bool)
    {
        return hasher.hashPaymentAsOperator(payment) == payment.seals.operator.hash;
    }

    function isGenuinePaymentWalletSeal(NahmiiTypesLib.Payment payment)
    public
    view
    returns (bool)
    {
        return isGenuinePaymentWalletHash(payment)
        && isGenuineWalletSignature(payment.seals.wallet.hash, payment.seals.wallet.signature, payment.sender.wallet);
    }

    function isGenuinePaymentOperatorSeal(NahmiiTypesLib.Payment payment)
    public
    view
    returns (bool)
    {
        return isGenuinePaymentOperatorHash(payment)
        && isGenuineOperatorSignature(payment.seals.operator.hash, payment.seals.operator.signature);
    }

    function isGenuinePaymentSeals(NahmiiTypesLib.Payment payment)
    public
    view
    returns (bool)
    {
        return isGenuinePaymentWalletSeal(payment) && isGenuinePaymentOperatorSeal(payment);
    }

    // @dev Logics of this function only applies to FT
    function isGenuinePaymentFeeOfFungible(NahmiiTypesLib.Payment payment)
    public
    view
    returns (bool)
    {
        int256 feePartsPer = int256(ConstantsLib.PARTS_PER());

        int256 feeAmount = payment.amount
        .mul(
            configuration.currencyPaymentFee(
                payment.blockNumber, payment.currency.ct, payment.currency.id, payment.amount
            )
        ).div(feePartsPer);

        if (1 > feeAmount)
            feeAmount = 1;

        return (payment.sender.fees.single.amount == feeAmount);
    }

    // @dev Logics of this function only applies to NFT
    function isGenuinePaymentFeeOfNonFungible(NahmiiTypesLib.Payment payment)
    public
    view
    returns (bool)
    {
        (address feeCurrencyCt, uint256 feeCurrencyId) = configuration.feeCurrency(
            payment.blockNumber, payment.currency.ct, payment.currency.id
        );

        return feeCurrencyCt == payment.sender.fees.single.currency.ct
        && feeCurrencyId == payment.sender.fees.single.currency.id;
    }

    // @dev Logics of this function only applies to FT
    function isGenuinePaymentSenderOfFungible(NahmiiTypesLib.Payment payment)
    public
    view
    returns (bool)
    {
        return (payment.sender.wallet != payment.recipient.wallet)
        && (!signerManager.isSigner(payment.sender.wallet))
        && (payment.sender.balances.current == payment.sender.balances.previous.sub(payment.transfers.single).sub(payment.sender.fees.single.amount));
    }

    // @dev Logics of this function only applies to FT
    function isGenuinePaymentRecipientOfFungible(NahmiiTypesLib.Payment payment)
    public
    pure
    returns (bool)
    {
        return (payment.sender.wallet != payment.recipient.wallet)
        && (payment.recipient.balances.current == payment.recipient.balances.previous.add(payment.transfers.single));
    }

    // @dev Logics of this function only applies to NFT
    function isGenuinePaymentSenderOfNonFungible(NahmiiTypesLib.Payment payment)
    public
    view
    returns (bool)
    {
        return (payment.sender.wallet != payment.recipient.wallet)
        && (!signerManager.isSigner(payment.sender.wallet));
    }

    // @dev Logics of this function only applies to NFT
    function isGenuinePaymentRecipientOfNonFungible(NahmiiTypesLib.Payment payment)
    public
    pure
    returns (bool)
    {
        return (payment.sender.wallet != payment.recipient.wallet);
    }

    function isSuccessiveTradesPartyNonces(
        NahmiiTypesLib.Trade firstTrade,
        NahmiiTypesLib.TradePartyRole firstTradePartyRole,
        NahmiiTypesLib.Trade lastTrade,
        NahmiiTypesLib.TradePartyRole lastTradePartyRole
    )
    public
    pure
    returns (bool)
    {
        uint256 firstNonce = (NahmiiTypesLib.TradePartyRole.Buyer == firstTradePartyRole ? firstTrade.buyer.nonce : firstTrade.seller.nonce);
        uint256 lastNonce = (NahmiiTypesLib.TradePartyRole.Buyer == lastTradePartyRole ? lastTrade.buyer.nonce : lastTrade.seller.nonce);
        return lastNonce == firstNonce.add(1);
    }

    function isSuccessivePaymentsPartyNonces(
        NahmiiTypesLib.Payment firstPayment,
        NahmiiTypesLib.PaymentPartyRole firstPaymentPartyRole,
        NahmiiTypesLib.Payment lastPayment,
        NahmiiTypesLib.PaymentPartyRole lastPaymentPartyRole
    )
    public
    pure
    returns (bool)
    {
        uint256 firstNonce = (NahmiiTypesLib.PaymentPartyRole.Sender == firstPaymentPartyRole ? firstPayment.sender.nonce : firstPayment.recipient.nonce);
        uint256 lastNonce = (NahmiiTypesLib.PaymentPartyRole.Sender == lastPaymentPartyRole ? lastPayment.sender.nonce : lastPayment.recipient.nonce);
        return lastNonce == firstNonce.add(1);
    }

    function isSuccessiveTradePaymentPartyNonces(
        NahmiiTypesLib.Trade trade,
        NahmiiTypesLib.TradePartyRole tradePartyRole,
        NahmiiTypesLib.Payment payment,
        NahmiiTypesLib.PaymentPartyRole paymentPartyRole
    )
    public
    pure
    returns (bool)
    {
        uint256 firstNonce = (NahmiiTypesLib.TradePartyRole.Buyer == tradePartyRole ? trade.buyer.nonce : trade.seller.nonce);
        uint256 lastNonce = (NahmiiTypesLib.PaymentPartyRole.Sender == paymentPartyRole ? payment.sender.nonce : payment.recipient.nonce);
        return lastNonce == firstNonce.add(1);
    }

    function isSuccessivePaymentTradePartyNonces(
        NahmiiTypesLib.Payment payment,
        NahmiiTypesLib.PaymentPartyRole paymentPartyRole,
        NahmiiTypesLib.Trade trade,
        NahmiiTypesLib.TradePartyRole tradePartyRole
    )
    public
    pure
    returns (bool)
    {
        uint256 firstNonce = (NahmiiTypesLib.PaymentPartyRole.Sender == paymentPartyRole ? payment.sender.nonce : payment.recipient.nonce);
        uint256 lastNonce = (NahmiiTypesLib.TradePartyRole.Buyer == tradePartyRole ? trade.buyer.nonce : trade.seller.nonce);
        return lastNonce == firstNonce.add(1);
    }

    function isGenuineSuccessiveTradesBalances(
        NahmiiTypesLib.Trade firstTrade,
        NahmiiTypesLib.TradePartyRole firstTradePartyRole,
        NahmiiTypesLib.CurrencyRole firstTradeCurrencyRole,
        NahmiiTypesLib.Trade lastTrade,
        NahmiiTypesLib.TradePartyRole lastTradePartyRole,
        NahmiiTypesLib.CurrencyRole lastTradeCurrencyRole
    )
    public
    pure
    returns (bool)
    {
        NahmiiTypesLib.IntendedConjugateCurrentPreviousInt256 memory firstIntendedConjugateCurrentPreviousBalances = (NahmiiTypesLib.TradePartyRole.Buyer == firstTradePartyRole ? firstTrade.buyer.balances : firstTrade.seller.balances);
        NahmiiTypesLib.CurrentPreviousInt256 memory firstCurrentPreviousBalances = (NahmiiTypesLib.CurrencyRole.Intended == firstTradeCurrencyRole ? firstIntendedConjugateCurrentPreviousBalances.intended : firstIntendedConjugateCurrentPreviousBalances.conjugate);

        NahmiiTypesLib.IntendedConjugateCurrentPreviousInt256 memory lastIntendedConjugateCurrentPreviousBalances = (NahmiiTypesLib.TradePartyRole.Buyer == lastTradePartyRole ? lastTrade.buyer.balances : lastTrade.seller.balances);
        NahmiiTypesLib.CurrentPreviousInt256 memory lastCurrentPreviousBalances = (NahmiiTypesLib.CurrencyRole.Intended == lastTradeCurrencyRole ? lastIntendedConjugateCurrentPreviousBalances.intended : lastIntendedConjugateCurrentPreviousBalances.conjugate);

        return lastCurrentPreviousBalances.previous == firstCurrentPreviousBalances.current;
    }

    function isGenuineSuccessivePaymentsBalances(
        NahmiiTypesLib.Payment firstPayment,
        NahmiiTypesLib.PaymentPartyRole firstPaymentPartyRole,
        NahmiiTypesLib.Payment lastPayment,
        NahmiiTypesLib.PaymentPartyRole lastPaymentPartyRole
    )
    public
    pure
    returns (bool)
    {
        NahmiiTypesLib.CurrentPreviousInt256 memory firstCurrentPreviousBalances = (NahmiiTypesLib.PaymentPartyRole.Sender == firstPaymentPartyRole ? firstPayment.sender.balances : firstPayment.recipient.balances);
        NahmiiTypesLib.CurrentPreviousInt256 memory lastCurrentPreviousBalances = (NahmiiTypesLib.PaymentPartyRole.Sender == lastPaymentPartyRole ? lastPayment.sender.balances : lastPayment.recipient.balances);

        return lastCurrentPreviousBalances.previous == firstCurrentPreviousBalances.current;
    }

    function isGenuineSuccessiveTradePaymentBalances(
        NahmiiTypesLib.Trade trade,
        NahmiiTypesLib.TradePartyRole tradePartyRole,
        NahmiiTypesLib.CurrencyRole tradeCurrencyRole,
        NahmiiTypesLib.Payment payment,
        NahmiiTypesLib.PaymentPartyRole paymentPartyRole
    )
    public
    pure
    returns (bool)
    {
        NahmiiTypesLib.IntendedConjugateCurrentPreviousInt256 memory firstIntendedConjugateCurrentPreviousBalances = (NahmiiTypesLib.TradePartyRole.Buyer == tradePartyRole ? trade.buyer.balances : trade.seller.balances);
        NahmiiTypesLib.CurrentPreviousInt256 memory firstCurrentPreviousBalances = (NahmiiTypesLib.CurrencyRole.Intended == tradeCurrencyRole ? firstIntendedConjugateCurrentPreviousBalances.intended : firstIntendedConjugateCurrentPreviousBalances.conjugate);

        NahmiiTypesLib.CurrentPreviousInt256 memory lastCurrentPreviousBalances = (NahmiiTypesLib.PaymentPartyRole.Sender == paymentPartyRole ? payment.sender.balances : payment.recipient.balances);

        return lastCurrentPreviousBalances.previous == firstCurrentPreviousBalances.current;
    }

    function isGenuineSuccessivePaymentTradeBalances(
        NahmiiTypesLib.Payment payment,
        NahmiiTypesLib.PaymentPartyRole paymentPartyRole,
        NahmiiTypesLib.Trade trade,
        NahmiiTypesLib.TradePartyRole tradePartyRole,
        NahmiiTypesLib.CurrencyRole tradeCurrencyRole
    )
    public
    pure
    returns (bool)
    {
        NahmiiTypesLib.CurrentPreviousInt256 memory firstCurrentPreviousBalances = (NahmiiTypesLib.PaymentPartyRole.Sender == paymentPartyRole ? payment.sender.balances : payment.recipient.balances);

        NahmiiTypesLib.IntendedConjugateCurrentPreviousInt256 memory firstIntendedConjugateCurrentPreviousBalances = (NahmiiTypesLib.TradePartyRole.Buyer == tradePartyRole ? trade.buyer.balances : trade.seller.balances);
        NahmiiTypesLib.CurrentPreviousInt256 memory lastCurrentPreviousBalances = (NahmiiTypesLib.CurrencyRole.Intended == tradeCurrencyRole ? firstIntendedConjugateCurrentPreviousBalances.intended : firstIntendedConjugateCurrentPreviousBalances.conjugate);

        return lastCurrentPreviousBalances.previous == firstCurrentPreviousBalances.current;
    }

    function isGenuineSuccessiveTradesTotalFees(
        NahmiiTypesLib.Trade firstTrade,
        NahmiiTypesLib.TradePartyRole firstTradePartyRole,
        NahmiiTypesLib.Trade lastTrade,
        NahmiiTypesLib.TradePartyRole lastTradePartyRole
    )
    public
    pure
    returns (bool)
    {
        MonetaryTypesLib.Figure memory lastSingleFee;
        if (NahmiiTypesLib.TradePartyRole.Buyer == lastTradePartyRole)
            lastSingleFee = lastTrade.buyer.fees.single;
        else if (NahmiiTypesLib.TradePartyRole.Seller == lastTradePartyRole)
            lastSingleFee = lastTrade.seller.fees.single;

        NahmiiTypesLib.OriginFigure[] memory firstTotalFees = (NahmiiTypesLib.TradePartyRole.Buyer == firstTradePartyRole ? firstTrade.buyer.fees.total : firstTrade.seller.fees.total);
        MonetaryTypesLib.Figure memory firstTotalFee = getProtocolFigureByCurrency(firstTotalFees, lastSingleFee.currency);

        NahmiiTypesLib.OriginFigure[] memory lastTotalFees = (NahmiiTypesLib.TradePartyRole.Buyer == lastTradePartyRole ? lastTrade.buyer.fees.total : lastTrade.seller.fees.total);
        MonetaryTypesLib.Figure memory lastTotalFee = getProtocolFigureByCurrency(lastTotalFees, lastSingleFee.currency);

        return lastTotalFee.amount == firstTotalFee.amount.add(lastSingleFee.amount);
    }

    function isGenuineSuccessiveTradeOrderResiduals(
        NahmiiTypesLib.Trade firstTrade,
        NahmiiTypesLib.Trade lastTrade,
        NahmiiTypesLib.TradePartyRole tradePartyRole
    )
    public
    pure
    returns (bool)
    {
        (int256 firstCurrentResiduals, int256 lastPreviousResiduals) = (NahmiiTypesLib.TradePartyRole.Buyer == tradePartyRole) ?
        (firstTrade.buyer.order.residuals.current, lastTrade.buyer.order.residuals.previous) :
    (firstTrade.seller.order.residuals.current, lastTrade.seller.order.residuals.previous);

        return firstCurrentResiduals == lastPreviousResiduals;
    }

    function isGenuineSuccessivePaymentsTotalFees(
        NahmiiTypesLib.Payment firstPayment,
        NahmiiTypesLib.Payment lastPayment
    )
    public
    pure
    returns (bool)
    {
        MonetaryTypesLib.Figure memory firstTotalFee = getProtocolFigureByCurrency(firstPayment.sender.fees.total, lastPayment.sender.fees.single.currency);
        MonetaryTypesLib.Figure memory lastTotalFee = getProtocolFigureByCurrency(lastPayment.sender.fees.total, lastPayment.sender.fees.single.currency);
        return lastTotalFee.amount == firstTotalFee.amount.add(lastPayment.sender.fees.single.amount);
    }

    function isGenuineSuccessiveTradePaymentTotalFees(
        NahmiiTypesLib.Trade trade,
        NahmiiTypesLib.TradePartyRole tradePartyRole,
        NahmiiTypesLib.Payment payment
    )
    public
    pure
    returns (bool)
    {
        NahmiiTypesLib.OriginFigure[] memory firstTotalFees = (NahmiiTypesLib.TradePartyRole.Buyer == tradePartyRole ? trade.buyer.fees.total : trade.seller.fees.total);
        MonetaryTypesLib.Figure memory firstTotalFee = getProtocolFigureByCurrency(firstTotalFees, payment.sender.fees.single.currency);

        MonetaryTypesLib.Figure memory lastTotalFee = getProtocolFigureByCurrency(payment.sender.fees.total, payment.sender.fees.single.currency);

        return lastTotalFee.amount == firstTotalFee.amount.add(payment.sender.fees.single.amount);
    }

    function isGenuineSuccessivePaymentTradeTotalFees(
        NahmiiTypesLib.Payment payment,
        NahmiiTypesLib.PaymentPartyRole paymentPartyRole,
        NahmiiTypesLib.Trade trade,
        NahmiiTypesLib.TradePartyRole tradePartyRole
    )
    public
    pure
    returns (bool)
    {
        MonetaryTypesLib.Figure memory lastSingleFee;
        if (NahmiiTypesLib.TradePartyRole.Buyer == tradePartyRole)
            lastSingleFee = trade.buyer.fees.single;
        else if (NahmiiTypesLib.TradePartyRole.Seller == tradePartyRole)
            lastSingleFee = trade.seller.fees.single;

        NahmiiTypesLib.OriginFigure[] memory firstTotalFees = (NahmiiTypesLib.PaymentPartyRole.Sender == paymentPartyRole ? payment.sender.fees.total : payment.recipient.fees.total);
        MonetaryTypesLib.Figure memory firstTotalFee = getProtocolFigureByCurrency(firstTotalFees, lastSingleFee.currency);

        NahmiiTypesLib.OriginFigure[] memory lastTotalFees = (NahmiiTypesLib.TradePartyRole.Buyer == tradePartyRole ? trade.buyer.fees.total : trade.seller.fees.total);
        MonetaryTypesLib.Figure memory lastTotalFee = getProtocolFigureByCurrency(lastTotalFees, lastSingleFee.currency);

        return lastTotalFee.amount == firstTotalFee.amount.add(lastSingleFee.amount);
    }

    function isTradeParty(NahmiiTypesLib.Trade trade, address wallet)
    public
    pure
    returns (bool)
    {
        return wallet == trade.buyer.wallet || wallet == trade.seller.wallet;
    }

    function isTradeBuyer(NahmiiTypesLib.Trade trade, address wallet)
    public
    pure
    returns (bool)
    {
        return wallet == trade.buyer.wallet;
    }

    function isTradeSeller(NahmiiTypesLib.Trade trade, address wallet)
    public
    pure
    returns (bool)
    {
        return wallet == trade.seller.wallet;
    }

    function isTradeOrder(NahmiiTypesLib.Trade trade, NahmiiTypesLib.Order order)
    public
    pure
    returns (bool)
    {
        return (trade.buyer.order.hashes.operator == order.seals.operator.hash ||
        trade.seller.order.hashes.operator == order.seals.operator.hash);
    }

    function isTradeIntendedCurrencyNonFungible(NahmiiTypesLib.Trade trade)
    public
    pure
    returns (bool)
    {
        return trade.currencies.intended.ct != trade.buyer.fees.single.currency.ct
        || trade.currencies.intended.id != trade.buyer.fees.single.currency.id;
    }

    function isTradeConjugateCurrencyNonFungible(NahmiiTypesLib.Trade trade)
    public
    pure
    returns (bool)
    {
        return trade.currencies.conjugate.ct != trade.seller.fees.single.currency.ct
        || trade.currencies.conjugate.id != trade.seller.fees.single.currency.id;
    }

    function isPaymentParty(NahmiiTypesLib.Payment payment, address wallet)
    public
    pure
    returns (bool)
    {
        return wallet == payment.sender.wallet || wallet == payment.recipient.wallet;
    }

    function isPaymentSender(NahmiiTypesLib.Payment payment, address wallet)
    public
    pure
    returns (bool)
    {
        return wallet == payment.sender.wallet;
    }

    function isPaymentRecipient(NahmiiTypesLib.Payment payment, address wallet)
    public
    pure
    returns (bool)
    {
        return wallet == payment.recipient.wallet;
    }

    function isPaymentCurrencyNonFungible(NahmiiTypesLib.Payment payment)
    public
    pure
    returns (bool)
    {
        return payment.currency.ct != payment.sender.fees.single.currency.ct
        || payment.currency.id != payment.sender.fees.single.currency.id;
    }

    //
    // Private unctions
    // -----------------------------------------------------------------------------------------------------------------
    function getProtocolFigureByCurrency(NahmiiTypesLib.OriginFigure[] originFigures, MonetaryTypesLib.Currency currency)
    private
    pure
    returns (MonetaryTypesLib.Figure) {
        for (uint256 i = 0; i < originFigures.length; i++)
            if (originFigures[i].figure.currency.ct == currency.ct && originFigures[i].figure.currency.id == currency.id
            && originFigures[i].originId == 0)
                return originFigures[i].figure;
        return MonetaryTypesLib.Figure(0, currency);
    }
}