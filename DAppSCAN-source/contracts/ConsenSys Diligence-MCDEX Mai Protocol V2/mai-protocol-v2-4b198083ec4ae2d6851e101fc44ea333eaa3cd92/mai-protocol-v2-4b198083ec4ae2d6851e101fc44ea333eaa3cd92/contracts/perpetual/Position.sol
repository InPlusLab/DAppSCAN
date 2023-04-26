pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";
import "../lib/LibTypes.sol";
import "./Collateral.sol";
import "./PerpetualGovernance.sol";


contract Position is Collateral, PerpetualGovernance {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;
    using LibTypes for LibTypes.Side;

    int256 public insuranceFundBalance;
    uint256[3] internal totalSizes;
    mapping(address => LibTypes.PositionAccount) internal positions;

    event SocialLoss(LibTypes.Side side, int256 newVal);
    event UpdatePositionAccount(
        address indexed guy,
        LibTypes.PositionAccount account,
        uint256 perpetualTotalSize,
        uint256 price
    );
    event UpdateInsuranceFund(int256 newVal);

    constructor(address collateral, uint256 collateralDecimals) public Collateral(collateral, collateralDecimals) {}

    // Public functions
    function socialLossPerContract(LibTypes.Side side) public view returns (int256) {
        return socialLossPerContracts[uint256(side)];
    }

    function totalSize(LibTypes.Side side) public view returns (uint256) {
        return totalSizes[uint256(side)];
    }

    function getPosition(address guy) public view returns (LibTypes.PositionAccount memory) {
        return positions[guy];
    }

    function calculateLiquidateAmount(address guy, uint256 liquidationPrice) public returns (uint256) {
        if (positions[guy].size == 0) {
            return 0;
        }
        LibTypes.PositionAccount memory account = positions[guy];
        int256 liquidationAmount = cashBalances[guy].balance.add(account.entrySocialLoss);
        liquidationAmount = liquidationAmount.sub(marginWithPrice(guy, liquidationPrice).toInt256()).sub(
            socialLossPerContract(account.side).wmul(account.size.toInt256())
        );
        int256 tmp = account
            .entryValue
            .toInt256()
            .sub(account.entryFundingLoss)
            .add(amm.currentAccumulatedFundingPerContract().wmul(account.size.toInt256()))
            .sub(account.size.wmul(liquidationPrice).toInt256());
        if (account.side == LibTypes.Side.LONG) {
            liquidationAmount = liquidationAmount.sub(tmp);
        } else if (account.side == LibTypes.Side.SHORT) {
            liquidationAmount = liquidationAmount.add(tmp);
        } else {
            return 0;
        }
        int256 denominator = governance
            .liquidationPenaltyRate
            .add(governance.penaltyFundRate)
            .toInt256()
            .sub(governance.initialMarginRate.toInt256())
            .wmul(liquidationPrice.toInt256());
        liquidationAmount = liquidationAmount.wdiv(denominator);
        liquidationAmount = liquidationAmount.max(0);
        liquidationAmount = liquidationAmount.min(account.size.toInt256());
        return liquidationAmount.toUint256();
    }

    // Internal functions
    function addSocialLossPerContract(LibTypes.Side side, int256 amount) internal {
        require(amount >= 0, "negtive social loss");
        int256 newVal = socialLossPerContracts[uint256(side)].add(amount);
        socialLossPerContracts[uint256(side)] = newVal;
        emit SocialLoss(side, newVal);
    }
    function marginBalanceWithPrice(address guy, uint256 markPrice) internal returns (int256) {
        return cashBalances[guy].balance.add(pnlWithPrice(guy, markPrice));
    }

    function availableMarginWithPrice(address guy, uint256 markPrice) internal returns (int256) {
        int256 p = marginBalanceWithPrice(guy, markPrice);
        p = p.sub(marginWithPrice(guy, markPrice).toInt256());
        p = p.sub(cashBalances[guy].appliedBalance);
        return p;
    }

    function marginWithPrice(address guy, uint256 markPrice) internal view returns (uint256) {
        return positions[guy].size.wmul(markPrice).wmul(governance.initialMarginRate);
    }

    function maintenanceMarginWithPrice(address guy, uint256 markPrice) internal view returns (uint256) {
        return positions[guy].size.wmul(markPrice).wmul(governance.maintenanceMarginRate);
    }

    function drawableBalanceWithPrice(address guy, uint256 markPrice) internal returns (int256) {
        return
            marginBalanceWithPrice(guy, markPrice).sub(marginWithPrice(guy, markPrice).toInt256()).min(
                cashBalances[guy].appliedBalance
            );
    }

    function pnlWithPrice(address guy, uint256 markPrice) internal returns (int256) {
        LibTypes.PositionAccount memory account = positions[guy];
        return calculatePnl(account, markPrice, account.size);
    }

    // Internal functions
    function increaseTotalSize(LibTypes.Side side, uint256 amount) internal {
        totalSizes[uint256(side)] = totalSizes[uint256(side)].add(amount);
    }

    function decreaseTotalSize(LibTypes.Side side, uint256 amount) internal {
        totalSizes[uint256(side)] = totalSizes[uint256(side)].sub(amount);
    }

    function socialLoss(LibTypes.PositionAccount memory account) internal view returns (int256) {
        return socialLossWithAmount(account, account.size);
    }

    function socialLossWithAmount(LibTypes.PositionAccount memory account, uint256 amount)
        internal
        view
        returns (int256)
    {
        int256 loss = socialLossPerContract(account.side).wmul(amount.toInt256());
        if (amount == account.size) {
            loss = loss.sub(account.entrySocialLoss);
        } else {
            // loss = loss.sub(account.entrySocialLoss.wmul(amount).wdiv(account.size));
            loss = loss.sub(account.entrySocialLoss.wfrac(amount.toInt256(), account.size.toInt256()));
            // prec error
            if (loss != 0) {
                loss = loss.add(1);
            }
        }
        return loss;
    }

    function fundingLoss(LibTypes.PositionAccount memory account) internal returns (int256) {
        return fundingLossWithAmount(account, account.size);
    }

    function fundingLossWithAmount(LibTypes.PositionAccount memory account, uint256 amount) internal returns (int256) {
        int256 loss = amm.currentAccumulatedFundingPerContract().wmul(amount.toInt256());
        if (amount == account.size) {
            loss = loss.sub(account.entryFundingLoss);
        } else {
            // loss = loss.sub(account.entryFundingLoss.wmul(amount.toInt256()).wdiv(account.size.toInt256()));
            loss = loss.sub(account.entryFundingLoss.wfrac(amount.toInt256(), account.size.toInt256()));
        }
        if (account.side == LibTypes.Side.SHORT) {
            loss = loss.neg();
        }
        if (loss != 0 && amount != account.size) {
            loss = loss.add(1);
        }
        return loss;
    }

    function remargin(address guy, uint256 markPrice) internal {
        LibTypes.PositionAccount storage account = positions[guy];
        if (account.size == 0) {
            return;
        }
        int256 rpnl = calculatePnl(account, markPrice, account.size);
        account.entryValue = markPrice.wmul(account.size);
        account.entrySocialLoss = socialLossPerContract(account.side).wmul(account.size.toInt256());
        account.entryFundingLoss = amm.currentAccumulatedFundingPerContract().wmul(account.size.toInt256());
        updateBalance(guy, rpnl);
        emit UpdatePositionAccount(guy, account, totalSize(LibTypes.Side.LONG), markPrice);
    }

    function calculatePnl(LibTypes.PositionAccount memory account, uint256 tradePrice, uint256 amount)
        internal
        returns (int256)
    {
        if (account.size == 0) {
            return 0;
        }
        int256 p1 = tradePrice.wmul(amount).toInt256();
        int256 p2;
        if (amount == account.size) {
            p2 = account.entryValue.toInt256();
        } else {
            // p2 = account.entryValue.wmul(amount).wdiv(account.size).toInt256();
            p2 = account.entryValue.wfrac(amount, account.size).toInt256();
        }
        int256 profit = account.side == LibTypes.Side.LONG ? p1.sub(p2) : p2.sub(p1);
        // prec error
        if (profit != 0) {
            profit = profit.sub(1);
        }
        int256 loss1 = socialLossWithAmount(account, amount);
        int256 loss2 = fundingLossWithAmount(account, amount);
        return profit.sub(loss1).sub(loss2);
    }

    function open(LibTypes.PositionAccount memory account, LibTypes.Side side, uint256 price, uint256 amount) internal {
        require(amount > 0, "open: invald amount");
        if (account.size == 0) {
            account.side = side;
        }
        account.size = account.size.add(amount);
        account.entryValue = account.entryValue.add(price.wmul(amount));
        account.entrySocialLoss = account.entrySocialLoss.add(socialLossPerContract(side).wmul(amount.toInt256()));
        account.entryFundingLoss = account.entryFundingLoss.add(
            amm.currentAccumulatedFundingPerContract().wmul(amount.toInt256())
        );
        increaseTotalSize(side, amount);
    }

    function close(LibTypes.PositionAccount memory account, uint256 price, uint256 amount) internal returns (int256) {
        int256 rpnl = calculatePnl(account, price, amount);
        account.entrySocialLoss = account.entrySocialLoss.wmul(account.size.sub(amount).toInt256()).wdiv(
            account.size.toInt256()
        );
        account.entryFundingLoss = account.entryFundingLoss.wmul(account.size.sub(amount).toInt256()).wdiv(
            account.size.toInt256()
        );
        account.entryValue = account.entryValue.wmul(account.size.sub(amount)).wdiv(account.size);
        account.size = account.size.sub(amount);
        decreaseTotalSize(account.side, amount);
        if (account.size == 0) {
            account.side = LibTypes.Side.FLAT;
        }
        return rpnl;
    }

    function trade(address guy, LibTypes.Side side, uint256 price, uint256 amount) internal returns (uint256) {
        int256 rpnl;
        uint256 opened = amount;
        uint256 closed;
        LibTypes.PositionAccount memory account = positions[guy];
        if (account.size > 0 && account.side != side) {
            closed = account.size.min(opened);
            rpnl = close(account, price, closed);
            opened = opened.sub(closed);
        }
        if (opened > 0) {
            open(account, side, price, opened);
        }
        updateBalance(guy, rpnl);
        positions[guy] = account;
        emit UpdatePositionAccount(guy, account, totalSize(LibTypes.Side.LONG), price);
        return opened;
    }

    function handleSocialLoss(LibTypes.Side side, int256 loss) internal {
        int256 newSocialLoss = loss.wdiv(totalSize(side).toInt256());
        addSocialLossPerContract(side, newSocialLoss);
    }

    function liquidate(address liquidator, address guy, uint256 liquidationPrice, uint256 liquidationAmount)
        internal
        returns (uint256)
    {
        // liquidiated trader
        LibTypes.PositionAccount memory account = positions[guy];
        LibTypes.Side liquidationSide = account.side;
        uint256 liquidationValue = liquidationPrice.wmul(liquidationAmount);
        int256 penaltyToLiquidator = governance.liquidationPenaltyRate.wmul(liquidationValue).toInt256();
        int256 penaltyToFund = governance.penaltyFundRate.wmul(liquidationValue).toInt256();
        int256 rpnl = close(account, liquidationPrice, liquidationAmount);
        positions[guy] = account;
        emit UpdatePositionAccount(guy, account, totalSize(LibTypes.Side.LONG), liquidationPrice);

        rpnl = rpnl.sub(penaltyToLiquidator).sub(penaltyToFund);
        updateBalance(guy, rpnl);
        int256 liquidationLoss = ensurePositiveBalance(guy).toInt256();

        // liquidator, penalty + poisition
        updateBalance(liquidator, penaltyToLiquidator);
        uint256 opened = trade(liquidator, liquidationSide, liquidationPrice, liquidationAmount);

        // fund, fund penalty - possible social loss
        insuranceFundBalance = insuranceFundBalance.add(penaltyToFund);
        if (insuranceFundBalance >= liquidationLoss) {
            insuranceFundBalance = insuranceFundBalance.sub(liquidationLoss);
        } else {
            int256 newSocialLoss = liquidationLoss.sub(insuranceFundBalance);
            insuranceFundBalance = 0;
            handleSocialLoss(liquidationSide, newSocialLoss);
        }
        require(insuranceFundBalance >= 0, "negtive insurance fund");

        emit UpdateInsuranceFund(insuranceFundBalance);
        return opened;
    }
}
