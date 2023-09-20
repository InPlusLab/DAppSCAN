// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./Common.sol";
import "./ExchangeRate.sol";

import "../lib/SafeInt256.sol";
import "../lib/SafeMath.sol";
import "../lib/SafeUInt128.sol";

import "../interface/IPortfoliosCallable.sol";
import "../storage/EscrowStorage.sol";

import "@openzeppelin/contracts/utils/SafeCast.sol";

library Liquidation {
    using SafeMath for uint256;
    using SafeInt256 for int256;
    using SafeUInt128 for uint128;

    // This buffer is used to account for the potential of decimal truncation causing accounts to be
    // permanently undercollateralized.
    int256 public constant LIQUIDATION_BUFFER = 1.01e18;

    struct TransferAmounts {
        int256 netLocalCurrencyLiquidator;
        uint128 netLocalCurrencyPayer;
        uint128 collateralTransfer;
        int256 payerCollateralBalance;
    }
//SWC-131-Presence of unused variables:L33
    struct CollateralCurrencyParameters {
        uint128 localCurrencyRequired;
        int256 localCurrencyAvailable;
        uint16 collateralCurrency;
        int256 collateralCurrencyCashClaim;
        int256 collateralCurrencyAvailable;
        uint128 discountFactor;
        uint128 liquidityHaircut;
        IPortfoliosCallable Portfolios;
    }

    struct RateParameters {
        uint256 rate;
        uint16 localCurrency;
        uint16 collateralCurrency;
        uint256 localDecimals;
        uint256 collateralDecimals;
        ExchangeRate.Rate localToETH;
    }

    /**
     * @notice Given an account that has liquidity tokens denominated in the currency, liquidates only enough to
     * recollateralize the account.
     * @param payer account that will be liquidated
     * @param localCurrency that the tokens will be denominated in
     * @param localCurrencyRequired the amount that we need to liquidate
     * @param liquidityHaircut the haircut on liquidity tokens
     * @param localCurrencyNetAvailable the amount of local currency we can liquidate up to
     * @param Portfolios the portfolio contract to call
     * @return (
     *   netLocalCurrencyLiquidator
     *   netLocalCurrencyPayer
     *   localCurrencyNetAvailable after the action,
     *   localCurrencyRequired after action
     *  )
     */
    function _liquidateLocalLiquidityTokens(
        address payer,
        uint16 localCurrency,
        uint128 localCurrencyRequired,
        uint128 liquidityHaircut,
        int256 localCurrencyNetAvailable,
        IPortfoliosCallable Portfolios
    ) internal returns (int256, uint128, int256, uint128) {
        // Calculate amount of liquidity tokens to withdraw and do the action.
        (uint128 cashClaimWithdrawn, uint128 localCurrencyRaised) = Liquidation._localLiquidityTokenTrade(
            payer,
            localCurrency,
            localCurrencyRequired,
            liquidityHaircut,
            Portfolios
        );

        // Calculates relevant parameters post trade.
        return _calculatePostTradeFactors(
            cashClaimWithdrawn,
            localCurrencyNetAvailable,
            localCurrencyRequired,
            localCurrencyRaised,
            liquidityHaircut
        );
    }

    /** @notice Trades liquidity tokens in order to attempt to raise `localCurrencyRequired` */
    function _localLiquidityTokenTrade(
        address account,
        uint16 currency,
        uint128 localCurrencyRequired,
        uint128 liquidityHaircut,
        IPortfoliosCallable Portfolios
    ) internal returns (uint128, uint128) {
        uint128 liquidityRepoIncentive = EscrowStorageSlot._liquidityTokenRepoIncentive();

        // We can only recollateralize the local currency using the part of the liquidity token that
        // between the pre-haircut cash claim and the post-haircut cash claim.
        // cashClaim - cashClaim * haircut = required * (1 + incentive)
        // cashClaim * (1 - haircut) = required * (1 + incentive)
        // cashClaim = required * (1 + incentive) / (1 - haircut)
        uint128 cashClaimsToTrade = SafeCast.toUint128(
            uint256(localCurrencyRequired)
                .mul(liquidityRepoIncentive)
                .div(Common.DECIMALS.sub(liquidityHaircut))
        );

        uint128 remainder = Portfolios.raiseCurrentCashViaLiquidityToken(
            account,
            currency,
            cashClaimsToTrade
        );

        uint128 localCurrencyRaised;
        uint128 cashClaimWithdrawn = cashClaimsToTrade.sub(remainder);
        if (remainder > 0) {
            // cashClaim = required * (1 + incentive) / (1 - haircut)
            // (cashClaim - remainder) = (required - delta) * (1 + incentive) / (1 - haircut)
            // cashClaimWithdrawn = (required - delta) * (1 + incentive) / (1 - haircut)
            // cashClaimWithdrawn * (1 - haircut) = (required - delta) * (1 + incentive)
            // cashClaimWithdrawn * (1 - haircut) / (1 + incentive) = (required - delta) = localCurrencyRaised
            localCurrencyRaised = SafeCast.toUint128(
                uint256(cashClaimWithdrawn)
                    .mul(Common.DECIMALS.sub(liquidityHaircut))
                    .div(liquidityRepoIncentive)
            );
        } else {
            localCurrencyRaised = localCurrencyRequired;
        }

        return (cashClaimWithdrawn, localCurrencyRaised);
    }

    function _calculatePostTradeFactors(
        uint128 cashClaimWithdrawn,
        int256 netCurrencyAvailable,
        uint128 localCurrencyRequired,
        uint128 localCurrencyRaised,
        uint128 liquidityHaircut
    ) internal pure returns (int256, uint128, int256, uint128) {
        // This is the portion of the cashClaimWithdrawn that is available to recollateralize the account.
        // cashClaimWithdrawn = value * (1 + incentive) / (1 - haircut)
        // cashClaimWithdrawn * (1 - haircut) = value * (1 + incentive)
        uint128 haircutClaimAmount = SafeCast.toUint128(
            uint256(cashClaimWithdrawn)
                .mul(Common.DECIMALS.sub(liquidityHaircut))
                .div(Common.DECIMALS)
        );


        // This is the incentive paid to the liquidator for extracting liquidity tokens.
        uint128 incentive = haircutClaimAmount.sub(localCurrencyRaised);

        return (
            int256(incentive).neg(),
            // This is what will be credited back to the account
            cashClaimWithdrawn.sub(incentive),
            // The haircutClaimAmount - incentive is added to netCurrencyAvailable because it is now recollateralizing the account. This
            // is used in the next step to guard against raising too much local currency (to the point where netCurrencyAvailable is positive)
            // such that additional local currency does not actually help the account's free collateral position.
            netCurrencyAvailable.add(haircutClaimAmount).sub(incentive),
            // The new local currency required is what we required before minus the amount we added to netCurrencyAvailable to
            // recollateralize the account in the previous step.
            localCurrencyRequired.add(incentive).sub(haircutClaimAmount)
        );
    }

    /**
     * @notice Liquidates an account, first attempting to extract liquidity tokens then moving on to collateral.
     * @param payer account that is being liquidated
     * @param payerCollateralBalance payer's collateral currency account balance
     * @param fc free collateral factors object
     * @param rateParam collateral currency exchange rate parameters
     * @param Portfolios address of portfolio contract to call
     */
    function liquidate(
        address payer,
        int256 payerCollateralBalance,
        Common.FreeCollateralFactors memory fc,
        RateParameters memory rateParam,
        address Portfolios
    ) public returns (TransferAmounts memory) {
        uint128 localCurrencyRequired = _fcAggregateToLocal(fc.aggregate, rateParam);

        TransferAmounts memory transfer = TransferAmounts(0, 0, 0, payerCollateralBalance);
        uint128 liquidityHaircut = EscrowStorageSlot._liquidityHaircut();
        if (fc.localCashClaim > 0) {
            // Account has a local currency cash claim denominated in liquidity tokens. We first extract that here.
            (
                transfer.netLocalCurrencyLiquidator,
                transfer.netLocalCurrencyPayer,
                fc.localNetAvailable,
                localCurrencyRequired
            ) = _liquidateLocalLiquidityTokens(
                payer,
                rateParam.localCurrency,
                localCurrencyRequired,
                liquidityHaircut,
                fc.localNetAvailable,
                IPortfoliosCallable(Portfolios)
            );
        }


        // If we still require more local currency and we have debts in the local currency then we will trade
        // collateral currency for local currency here.
        if (localCurrencyRequired > 0 && fc.localNetAvailable < 0) {
            _liquidateCollateralCurrency(
                payer,
                localCurrencyRequired,
                liquidityHaircut,
                transfer,
                fc,
                rateParam,
                Portfolios
            );
        }

        return transfer;
    }


    function _fcAggregateToLocal(
        int256 fcAggregate,
        RateParameters memory rateParam
    ) internal view returns (uint128) {
        // Safety check
        require(fcAggregate < 0);

        return uint128(
            ExchangeRate._convertETHTo(
                rateParam.localToETH,
                rateParam.localDecimals,
                fcAggregate.mul(LIQUIDATION_BUFFER).div(Common.DECIMALS).neg()
            )
        );
    }

    /**
     * @notice Settles current debts using collateral currency. First attempst to raise cash in local currency liquidity tokens before moving
     * on to collateral currency.
     * @param payer account that has current debts
     * @param payerCollateralBalance payer's collateral currency account balance
     * @param fc free collateral factors object
     * @param rateParam collateral currency exchange rate parameters
     * @param Portfolios address of portfolio contract to call
     */
    function settle(
        address payer,
        int256 payerCollateralBalance,
        uint128 valueToSettle,
        Common.FreeCollateralFactors memory fc,
        RateParameters memory rateParam,
        address Portfolios
    ) public returns (TransferAmounts memory) {
        TransferAmounts memory transfer = TransferAmounts(0, 0, 0, payerCollateralBalance);
        if (fc.localCashClaim > 0) {
            uint128 remainder = IPortfoliosCallable(Portfolios).raiseCurrentCashViaLiquidityToken(
                payer,
                rateParam.localCurrency,
                valueToSettle
            );

            transfer.netLocalCurrencyPayer = valueToSettle.sub(remainder);

            if (transfer.netLocalCurrencyPayer > fc.localCashClaim) {
                // If this is the case then we've raised cash that sits inside the haircut of the liquidity token
                // and it will add collateral to the account. We calculate these factors here before moving on.
                uint128 haircutAmount = transfer.netLocalCurrencyPayer.sub(uint128(fc.localCashClaim));

                int256 netFC = ExchangeRate._convertToETH(
                    rateParam.localToETH,
                    rateParam.localDecimals,
                    haircutAmount,
                    fc.localNetAvailable < 0
                );

                fc.aggregate = fc.aggregate.add(netFC);
            }
        }

        if (valueToSettle > transfer.netLocalCurrencyPayer && fc.aggregate >= 0) {
            uint128 liquidityHaircut = EscrowStorageSlot._liquidityHaircut();
            uint128 settlementDiscount = EscrowStorageSlot._settlementDiscount();
            uint128 localCurrencyRequired = valueToSettle.sub(transfer.netLocalCurrencyPayer);

            _tradeCollateralCurrency(
                payer,
                localCurrencyRequired,
                liquidityHaircut,
                settlementDiscount,
                transfer,
                fc,
                rateParam,
                Portfolios
            );
        }

        return transfer;
    }

    function _calculateLocalCurrencyToTrade(
        uint128 localCurrencyRequired,
        uint128 liquidationDiscount,
        uint128 localCurrencyBuffer,
        uint128 maxLocalCurrencyDebt
    ) internal pure returns (uint128) {
        // We calculate the max amount of local currency that the liquidator can trade for here. We set it to the min of the
        // netCurrencyAvailable and the localCurrencyToTrade figure calculated below. The math for this figure is as follows:

        // The benefit given to free collateral in local currency terms:
        //   localCurrencyBenefit = localCurrencyToTrade * localCurrencyBuffer
        // NOTE: this only holds true while maxLocalCurrencyDebt <= 0

        // The penalty for trading collateral currency in local currency terms:
        //   localCurrencyPenalty = collateralCurrencyPurchased * exchangeRate[collateralCurrency][localCurrency]
        //
        //  netLocalCurrencyBenefit = localCurrencyBenefit - localCurrencyPenalty
        //
        // collateralCurrencyPurchased = localCurrencyToTrade * exchangeRate[localCurrency][collateralCurrency] * liquidationDiscount
        // localCurrencyPenalty = localCurrencyToTrade * exchangeRate[localCurrency][collateralCurrency] * exchangeRate[collateralCurrency][localCurrency] * liquidationDiscount
        // localCurrencyPenalty = localCurrencyToTrade * liquidationDiscount
        // netLocalCurrencyBenefit =  localCurrencyToTrade * localCurrencyBuffer - localCurrencyToTrade * liquidationDiscount
        // netLocalCurrencyBenefit =  localCurrencyToTrade * (localCurrencyBuffer - liquidationDiscount)
        // localCurrencyToTrade =  netLocalCurrencyBenefit / (buffer - discount)
        //
        // localCurrencyRequired is netLocalCurrencyBenefit after removing liquidity tokens
        // localCurrencyToTrade =  localCurrencyRequired / (buffer - discount)

        uint128 localCurrencyToTrade = SafeCast.toUint128(
            uint256(localCurrencyRequired)
                .mul(Common.DECIMALS)
                .div(localCurrencyBuffer.sub(liquidationDiscount))
        );

        // We do not trade past the amount of local currency debt the account has or this benefit will not longer be effective.
        localCurrencyToTrade = maxLocalCurrencyDebt < localCurrencyToTrade ? maxLocalCurrencyDebt : localCurrencyToTrade;

        return localCurrencyToTrade;
    }

    function _liquidateCollateralCurrency(
        address payer,
        uint128 localCurrencyRequired,
        uint128 liquidityHaircut,
        TransferAmounts memory transfer,
        Common.FreeCollateralFactors memory fc,
        RateParameters memory rateParam,
        address Portfolios
    ) internal {
        uint128 discountFactor = EscrowStorageSlot._liquidationDiscount();
        localCurrencyRequired = _calculateLocalCurrencyToTrade(
            localCurrencyRequired,
            discountFactor,
            rateParam.localToETH.buffer,
            uint128(fc.localNetAvailable.neg())
        );

        _tradeCollateralCurrency(
            payer,
            localCurrencyRequired,
            liquidityHaircut,
            discountFactor,
            transfer,
            fc,
            rateParam,
            Portfolios
        );
    }

    function _tradeCollateralCurrency(
        address payer,
        uint128 localCurrencyRequired,
        uint128 liquidityHaircut,
        uint128 discountFactor,
        TransferAmounts memory transfer,
        Common.FreeCollateralFactors memory fc,
        RateParameters memory rateParam,
        address Portfolios
    ) internal {
        uint128 amountToRaise;
        uint128 localToPurchase;

        uint128 haircutClaim = _calculateLiquidityTokenHaircut(
            fc.collateralCashClaim,
            liquidityHaircut
        );

        int256 collateralToSell = _calculateCollateralToSell(
            discountFactor,
            localCurrencyRequired,
            rateParam
        );

        // It's possible that collateralToSell is zero even if localCurrencyRequired > 0, this can be caused
        // by very small amounts of localCurrencyRequired
        if (collateralToSell == 0) return;
        
        int256 balanceAdjustment;
        (fc.collateralNetAvailable, balanceAdjustment) = _calculatePostfCashValue(fc, transfer);
        require(fc.collateralNetAvailable > 0, $$(ErrorCode(INSUFFICIENT_BALANCE)));

        (amountToRaise, localToPurchase, transfer.collateralTransfer) = _calculatePurchaseAmounts(
            localCurrencyRequired,
            discountFactor,
            liquidityHaircut,
            haircutClaim,
            collateralToSell,
            fc,
            rateParam
        );

        // The result of this calculation is a new collateral currency balance for the payer.
        transfer.payerCollateralBalance = _calculateCollateralBalances(
            payer,
            transfer.payerCollateralBalance.add(balanceAdjustment),
            rateParam.collateralCurrency,
            transfer.collateralTransfer,
            amountToRaise,
            IPortfoliosCallable(Portfolios)
        );

        transfer.payerCollateralBalance = transfer.payerCollateralBalance.sub(balanceAdjustment);
        transfer.netLocalCurrencyPayer = transfer.netLocalCurrencyPayer.add(localToPurchase);
        transfer.netLocalCurrencyLiquidator = transfer.netLocalCurrencyLiquidator.add(localToPurchase);
    }

    /**
     * @notice Calculates collateralNetAvailable and payerCollateralBalance post fCashValue. We do not trade fCashValue
     * in this scenario so we want to only allow fCashValue to net out against negative collateral balance and no more.
     */
    function _calculatePostfCashValue(
        Common.FreeCollateralFactors memory fc,
        TransferAmounts memory transfer
    ) internal pure returns (int256, int256) {
        int256 fCashValue = fc.collateralNetAvailable
            .sub(transfer.payerCollateralBalance)
            .sub(fc.collateralCashClaim);

        if (fCashValue <= 0) {
            // If we have negative fCashValue then no adjustments are required.
            return (fc.collateralNetAvailable, 0);
        }

        if (transfer.payerCollateralBalance >= 0) {
            // If payer has a positive collateral balance then we don't need to net off against it. We remove
            // the fCashValue from net available.
            return (fc.collateralNetAvailable.sub(fCashValue), 0);
        }

        // In these scenarios the payer has a negative collateral balance and we need to partially offset the balance
        // so that the payer gets the benefit of their positive fCashValue.
        int256 netBalanceWithfCashValue = transfer.payerCollateralBalance.add(fCashValue);
        if (netBalanceWithfCashValue > 0) {
            // We have more fCashValue than required to net out the balance. We remove the excess from collateralNetAvailable
            // and adjust the netPayerBalance to zero.
            return (fc.collateralNetAvailable.sub(netBalanceWithfCashValue), transfer.payerCollateralBalance.neg());
        } else {
            // We don't have enough fCashValue to net out the balance. collateralNetAvailable is unchanged because it already takes
            // into account this netting. We adjust the balance to account for fCash only
            return (fc.collateralNetAvailable, fCashValue);
        }
    }

    function _calculateLiquidityTokenHaircut(
        int256 postHaircutCashClaim,
        uint128 liquidityHaircut
    ) internal pure returns (uint128) {
        require(postHaircutCashClaim >= 0);
        // liquidityTokenHaircut = cashClaim / haircut - cashClaim
        uint256 x = uint256(postHaircutCashClaim);

        return SafeCast.toUint128(
            uint256(x)
                .mul(Common.DECIMALS)
                .div(liquidityHaircut)
                .sub(x)
        );
    }

    function _calculatePurchaseAmounts(
        uint128 localCurrencyRequired,
        uint128 discountFactor,
        uint128 liquidityHaircut,
        uint128 haircutClaim,
        int256 collateralToSell,
        Common.FreeCollateralFactors memory fc,
        RateParameters memory rateParam
    ) internal pure returns (uint128, uint128, uint128) {
        require(fc.collateralNetAvailable > 0, $$(ErrorCode(INSUFFICIENT_BALANCE)));

        uint128 localToPurchase;
        uint128 amountToRaise;
        // This calculation is described in Appendix B of the whitepaper. It is split between this function and
        // _calculateCollateralBalances to deal with stack issues.
        if (fc.collateralNetAvailable >= collateralToSell) {
            // We have enough collateral currency available to fulfill the purchase. It is either locked up inside
            // liquidity tokens or in the account's balance. If the account's balance is negative then we will have
            // to raise additional amount to fulfill collateralToSell.
            localToPurchase = localCurrencyRequired;
        } else if (fc.collateralNetAvailable.add(haircutClaim) >= collateralToSell) {
            // We have enough collateral currency available if we account for the liquidity token haircut that
            // is not part of the collateralNetAvailable figure. Here we raise an additional amount. 

            // This has to be scaled to the preHaircutCashClaim amount:
            // haircutClaim = preHaircutCashClaim - preHaircutCashClaim * haircut
            // haircutClaim = preHaircutCashClaim * (1 - haircut)
            // liquidiytTokenHaircut / (1 - haircut) = preHaircutCashClaim
            amountToRaise = SafeCast.toUint128(
                uint256(collateralToSell.sub(fc.collateralNetAvailable))
                    .mul(Common.DECIMALS)
                    .div(Common.DECIMALS.sub(liquidityHaircut))
            );
            localToPurchase = localCurrencyRequired;
        } else if (collateralToSell > fc.collateralNetAvailable.add(haircutClaim)) {
            // There is not enough value collateral currency in the account to fulfill the purchase, we
            // specify the maximum amount that we can get from the account to partially settle.
            collateralToSell = fc.collateralNetAvailable.add(haircutClaim);

            // stack frame isn't big enough for this calculation
            // haircutClaim * 1e18 / (1e18 - liquidityHaircut), this is the maximum amountToRaise
            uint256 x = haircutClaim.mul(Common.DECIMALS);
            x = x.div(Common.DECIMALS.sub(liquidityHaircut));
            amountToRaise = SafeCast.toUint128(x);

            // In this case we partially settle the collateralToSell amount.
            require(collateralToSell > 0);
            localToPurchase = _calculateLocalCurrencyAmount(discountFactor, uint128(collateralToSell), rateParam);
        }

        require(collateralToSell > 0);

        return (amountToRaise, localToPurchase, uint128(collateralToSell));
    }

    function _calculateLocalCurrencyAmount(
        uint128 discountFactor,
        uint128 collateralToSell,
        RateParameters memory rateParam
    ) internal pure returns (uint128) {
        // collateralDecimals * rateDecimals * 1e18 * localDecimals
        //         / (rateDecimals * 1e18 * collateralDecimals) = localDecimals
        uint256 x = uint256(collateralToSell)
            .mul(rateParam.localToETH.rateDecimals)
            // Discount factor uses 1e18 as its decimal precision
            .mul(Common.DECIMALS);

        x = x
            .mul(rateParam.localDecimals)
            .div(rateParam.rate);

        return SafeCast.toUint128(x
            .div(discountFactor)
            .div(rateParam.collateralDecimals)
        );
    }

    function _calculateCollateralToSell(
        uint128 discountFactor,
        uint128 localCurrencyRequired,
        RateParameters memory rateParam
    ) internal pure returns (uint128) {
        uint256 x = rateParam.rate
            .mul(localCurrencyRequired)
            .mul(discountFactor);

        x = x
            .div(rateParam.localToETH.rateDecimals)
            .div(rateParam.localDecimals);
        
        // Splitting calculation to handle stack depth
        return SafeCast.toUint128(x
            // Multiplying to the quote decimal precision (may not be the same as the rate precision)
            .mul(rateParam.collateralDecimals)
            // discountFactor uses 1e18 as its decimal precision
            .div(Common.DECIMALS)
        );
    }

    function _calculateCollateralBalances(
        address payer,
        int256 payerBalance,
        uint16 collateralCurrency,
        uint128 collateralToSell,
        uint128 amountToRaise,
        IPortfoliosCallable Portfolios
    ) internal returns (int256) {
        // We must deterimine how to transfer collateral from the payer to liquidator. The collateral may be in cashBalances
        // or it may be locked up in liquidity tokens.
        int256 balance = payerBalance;
        bool creditBalance;

        if (balance >= collateralToSell) {
            balance = balance.sub(collateralToSell);
            creditBalance = true;
        } else {
            // If amountToRaise is greater than (collateralToSell - balance) this means that we're tapping into the
            // haircut claim amount. We need to credit back the difference to the account to ensure that the collateral
            // position does not get worse.
            int256 x = int256(collateralToSell).sub(balance);
            require(x > 0);
            uint128 tmp = uint128(x);

            if (amountToRaise > tmp) {
                balance = int256(amountToRaise).sub(tmp);
            } else {
                amountToRaise = tmp;
                balance = 0;
            }

            creditBalance = false;
        }

        if (amountToRaise > 0) {
            uint128 remainder = Portfolios.raiseCurrentCashViaLiquidityToken(
                payer,
                collateralCurrency,
                amountToRaise
            );

            if (creditBalance) {
                balance = balance.add(amountToRaise).sub(remainder);
            } else {
                // Generally we expect remainder to equal zero but this can be off by small amounts due
                // to truncation in the different calculations on the liquidity token haircuts. The upper bound on
                // amountToRaise is based on collateralCurrencyAvailable and the balance. Also note that when removing
                // liquidity tokens some amount of cash receiver is credited back to the account as well. The concern
                // here is that if this is not true then remainder could put the account into a debt that it cannot pay off.
                require(remainder <= 1, $$(ErrorCode(RAISING_LIQUIDITY_TOKEN_BALANCE_ERROR)));
                balance = balance.sub(remainder);
            }
        }

        return balance;
    }

    /**
     * @notice Settles fCash between local and collateral currency.
     * @param payer address of account that has current cash debts
     * @param liquidator address of account liquidating
     * @param valueToSettle amount of local currency debt to settle
     * @param collateralNetAvailable net amount of collateral available to trade
     * @param rateParam exchange rate parameters
     * @param Portfolios address of the portfolios contract
     */
    function settlefCash(
        address payer,
        address liquidator,
        uint128 valueToSettle,
        int256 collateralNetAvailable,
        RateParameters memory rateParam,
        address Portfolios
    ) public returns (int256, uint128) {
        uint128 discountFactor = EscrowStorageSlot._settlementDiscount();

        return _tradefCash(
            payer,
            liquidator,
            valueToSettle,
            collateralNetAvailable,
            discountFactor,
            rateParam,
            Portfolios
        );
    }

    /**
     * @notice Liquidates fCash between local and collateral currency.
     * @param payer address of account that has current cash debts
     * @param liquidator address of account liquidating
     * @param fcAggregate free collateral shortfall denominated in ETH
     * @param localNetAvailable amount of local currency debts available to recollateralize, dictates max trading amount
     * @param collateralNetAvailable net amount of collateral available to trade
     * @param rateParam exchange rate parameters
     * @param Portfolios address of the portfolios contract
     */
    function liquidatefCash(
        address payer,
        address liquidator,
        int256 fcAggregate,
        int256 localNetAvailable,
        int256 collateralNetAvailable,
        RateParameters memory rateParam,
        address Portfolios
    ) public returns (int256, uint128) {
        uint128 localCurrencyRequired = _fcAggregateToLocal(fcAggregate, rateParam);
        uint128 discountFactor = EscrowStorageSlot._liquidationDiscount();
        require (localNetAvailable < 0, $$(ErrorCode(INSUFFICIENT_LOCAL_CURRENCY_DEBT)));

        localCurrencyRequired = _calculateLocalCurrencyToTrade(
            localCurrencyRequired,
            discountFactor,
            rateParam.localToETH.buffer,
            uint128(localNetAvailable.neg())
        );

        return _tradefCash(
            payer,
            liquidator,
            localCurrencyRequired,
            collateralNetAvailable,
            discountFactor,
            rateParam,
            Portfolios
        );
    }

    /** @notice Trades fCash denominated in collateral currency in exchange for local currency. */
    function _tradefCash(
        address payer,
        address liquidator,
        uint128 localCurrencyRequired,
        int256 collateralNetAvailable,
        uint128 discountFactor,
        RateParameters memory rateParam,
        address Portfolios
    ) internal returns (int256, uint128) {
        require(collateralNetAvailable > 0, $$(ErrorCode(MUST_HAVE_NET_POSITIVE_COLLATERAL)));

        uint128 collateralCurrencyRequired = _calculateCollateralToSell(discountFactor, localCurrencyRequired, rateParam);
        if (collateralCurrencyRequired > collateralNetAvailable) {
            // We limit trading to the amount of collateralNetAvailable so that we don't put the account further undercollateralized
            // in the collateral currency.
            collateralCurrencyRequired = uint128(collateralNetAvailable);
            localCurrencyRequired = _calculateLocalCurrencyAmount(
                discountFactor,
                collateralCurrencyRequired,
                rateParam
            );
        }

        (uint128 shortfall, uint128 liquidatorPayment) = IPortfoliosCallable(Portfolios).raiseCurrentCashViaCashReceiver(
            payer,
            liquidator,
            rateParam.collateralCurrency,
            collateralCurrencyRequired
        );

        int256 netCollateralCurrencyLiquidator = int256(liquidatorPayment).sub(collateralCurrencyRequired.sub(shortfall));

        uint128 netLocalCurrencyPayer = localCurrencyRequired;
        if (shortfall > 0) {
            // (rate * discountFactor * (localCurrencyRequired - localShortfall)) = (collateralToSell - shortfall)
            // (rate * discountFactor * localShortfall) = shortfall
            // shortfall / (rate * discountFactor) = localCurrencyShortfall
            uint128 localCurrencyShortfall = 
                _calculateLocalCurrencyAmount(
                    discountFactor,
                    shortfall,
                    rateParam
                );

            netLocalCurrencyPayer = netLocalCurrencyPayer.sub(localCurrencyShortfall);
        }

        return (netCollateralCurrencyLiquidator, netLocalCurrencyPayer);
    }
}