pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "./LibOrder.sol";


library LibTypes {
    enum Side {FLAT, SHORT, LONG}

    enum Status {NORMAL, SETTLING, SETTLED}

    function counterSide(Side side) internal pure returns (Side) {
        if (side == Side.LONG) {
            return Side.SHORT;
        } else if (side == Side.SHORT) {
            return Side.LONG;
        }
        return side;
    }

    //////////////////////////////////////////////////////////////////////////
    // Perpetual
    //////////////////////////////////////////////////////////////////////////
    struct PerpGovernanceConfig {
        uint256 initialMarginRate;
        uint256 maintenanceMarginRate;
        uint256 liquidationPenaltyRate;
        uint256 penaltyFundRate;
        int256 takerDevFeeRate;
        int256 makerDevFeeRate;
        uint256 lotSize;
        uint256 tradingLotSize;
    }

    // CollateralAccount represents cash account of user
    struct CollateralAccount {
        // currernt deposited erc20 token amount, representing in decimals 18
        int256 balance;
        // the amount of withdrawal applied by user
        // which allowed to withdraw in the future but not available in trading
        int256 appliedBalance;
        // applied balance will be appled only when the block height below is reached
        uint256 appliedHeight;
    }

    struct PositionAccount {
        LibTypes.Side side;
        uint256 size;
        uint256 entryValue;
        int256 entrySocialLoss;
        int256 entryFundingLoss;
    }

    struct BrokerRecord {
        address broker;
        uint256 appliedHeight;
    }

    struct Broker {
        BrokerRecord previous;
        BrokerRecord current;
    }

    //////////////////////////////////////////////////////////////////////////
    // AMM
    //////////////////////////////////////////////////////////////////////////
    struct AMMGovernanceConfig {
        uint256 poolFeeRate;
        uint256 poolDevFeeRate;
        int256 emaAlpha;
        uint256 updatePremiumPrize;
        int256 markPremiumLimit;
        int256 fundingDampener;
    }

    struct FundingState {
        uint256 lastFundingTime;
        int256 lastPremium;
        int256 lastEMAPremium;
        uint256 lastIndexPrice;
        int256 accumulatedFundingPerContract;
    }
}
