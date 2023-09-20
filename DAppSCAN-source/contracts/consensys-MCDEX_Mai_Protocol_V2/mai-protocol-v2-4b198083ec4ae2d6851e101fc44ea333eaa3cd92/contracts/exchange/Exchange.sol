pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "../lib/LibMath.sol";
import "../lib/LibOrder.sol";
import "../lib/LibSignature.sol";
import "../interface/IPerpetual.sol";
import "../interface/IAMM.sol";


contract Exchange {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;
    using LibOrder for LibOrder.Order;
    using LibOrder for LibOrder.OrderParam;
    using LibSignature for LibSignature.OrderSignature;

    uint256 public constant SUPPORTED_ORDER_VERSION = 2;
    // SWC-131-Presence of unused variables: L20
    enum OrderStatus {EXPIRED, CANCELLED, FILLABLE, FULLY_FILLED}

    mapping(bytes32 => uint256) public filled;
    mapping(bytes32 => bool) public cancelled;

    event MatchWithOrders(
        address perpetual,
        LibOrder.OrderParam takerOrderParam,
        LibOrder.OrderParam makerOrderParam,
        uint256 amount
    );
    event MatchWithAMM(address perpetual, LibOrder.OrderParam takerOrderParam, uint256 amount);
    event Cancel(bytes32 indexed orderHash);

    function matchOrders(
        LibOrder.OrderParam memory takerOrderParam,
        LibOrder.OrderParam[] memory makerOrderParams,
        address _perpetual,
        uint256[] memory amounts
    ) public {
        require(!takerOrderParam.isMakerOnly(), "taker order is maker only");

        IPerpetual perpetual = IPerpetual(_perpetual);
        require(perpetual.status() == LibTypes.Status.NORMAL, "wrong perpetual status");

        uint256 tradingLotSize = perpetual.getGovernance().tradingLotSize;
        bytes32 takerOrderHash = validateOrderParam(perpetual, takerOrderParam);
        uint256 takerFilledAmount = filled[takerOrderHash];
        uint256 takerOpened;

        for (uint256 i = 0; i < makerOrderParams.length; i++) {
            require(takerOrderParam.trader != makerOrderParams[i].trader, "self trade");
            require(takerOrderParam.isInversed() == makerOrderParams[i].isInversed(), "invalid inversed pair");
            require(takerOrderParam.isSell() != makerOrderParams[i].isSell(), "invalid side");
            require(!makerOrderParams[i].isMarketOrder(), "market order cannot be maker");

            validatePrice(takerOrderParam, makerOrderParams[i]);

            bytes32 makerOrderHash = validateOrderParam(perpetual, makerOrderParams[i]);
            uint256 makerFilledAmount = filled[makerOrderHash];

            require(amounts[i] <= takerOrderParam.amount.sub(takerFilledAmount), "taker overfilled");
            require(amounts[i] <= makerOrderParams[i].amount.sub(makerFilledAmount), "maker overfilled");
            require(amounts[i].mod(tradingLotSize) == 0, "invalid trading lot size");

            uint256 opened = fillOrder(perpetual, takerOrderParam, makerOrderParams[i], amounts[i]);

            takerOpened = takerOpened.add(opened);
            filled[makerOrderHash] = makerFilledAmount.add(amounts[i]);
            takerFilledAmount = takerFilledAmount.add(amounts[i]);
        }

        // all trades done, check taker safe.
        if (takerOpened > 0) {
            require(perpetual.isIMSafe(takerOrderParam.trader), "taker margin");
        } else {
            require(perpetual.isSafe(takerOrderParam.trader), "maker unsafe");
        }
        require(perpetual.isSafe(msg.sender), "broker unsafe");

        filled[takerOrderHash] = takerFilledAmount;
    }

    function fillOrder(
        IPerpetual perpetual,
        LibOrder.OrderParam memory takerOrderParam,
        LibOrder.OrderParam memory makerOrderParam,
        uint256 amount
    ) internal returns (uint256) {
        uint256 price = makerOrderParam.getPrice();
        uint256 takerOpened = perpetual.tradePosition(takerOrderParam.trader, takerOrderParam.side(), price, amount);
        uint256 makerOpened = perpetual.tradePosition(makerOrderParam.trader, makerOrderParam.side(), price, amount);

        // trading fee
        int256 takerTradingFee = amount.wmul(price).toInt256().wmul(takerOrderParam.takerFeeRate());
        claimTradingFee(perpetual, takerOrderParam.trader, takerTradingFee);
        int256 makerTradingFee = amount.wmul(price).toInt256().wmul(makerOrderParam.makerFeeRate());
        claimTradingFee(perpetual, makerOrderParam.trader, makerTradingFee);

        // dev fee
        claimTakerDevFee(perpetual, takerOrderParam.trader, price, takerOpened, amount.sub(takerOpened));
        claimMakerDevFee(perpetual, makerOrderParam.trader, price, makerOpened, amount.sub(makerOpened));
        if (makerOpened > 0) {
            require(perpetual.isIMSafe(makerOrderParam.trader), "maker margin");
        } else {
            require(perpetual.isSafe(makerOrderParam.trader), "maker unsafe");
        }

        emit MatchWithOrders(address(perpetual), takerOrderParam, makerOrderParam, amount);

        return takerOpened;
    }

    function matchOrderWithAMM(LibOrder.OrderParam memory takerOrderParam, address _perpetual, uint256 amount) public {
        require(!takerOrderParam.isMakerOnly(), "taker order is maker only");

        IPerpetual perpetual = IPerpetual(_perpetual);
        IAMM amm = IAMM(perpetual.amm());

        require(amount.mod(perpetual.getGovernance().tradingLotSize) == 0, "invalid trading lot size");

        bytes32 takerOrderHash = validateOrderParam(perpetual, takerOrderParam);
        uint256 takerFilledAmount = filled[takerOrderHash];
        require(amount <= takerOrderParam.amount.sub(takerFilledAmount), "taker overfilled");

        // trading with pool
        uint256 takerOpened;
        uint256 price = takerOrderParam.getPrice();
        if (takerOrderParam.isSell()) {
            takerOpened = amm.sellFromWhitelisted(
                takerOrderParam.trader,
                amount,
                price,
                takerOrderParam.getExpiredAt()
            );
        } else {
            takerOpened = amm.buyFromWhitelisted(takerOrderParam.trader, amount, price, takerOrderParam.getExpiredAt());
        }
        filled[takerOrderHash] = filled[takerOrderHash].add(amount);

        emit MatchWithAMM(_perpetual, takerOrderParam, amount);
    }

    function validatePrice(LibOrder.OrderParam memory takerOrderParam, LibOrder.OrderParam memory makerOrderParam)
        internal
        pure
    {
        if (takerOrderParam.isMarketOrder()) {
            return;
        }
        uint256 takerPrice = takerOrderParam.getPrice();
        uint256 makerPrice = makerOrderParam.getPrice();
        require(takerOrderParam.isSell() ? takerPrice <= makerPrice : takerPrice >= makerPrice, "price not match");
    }

    function validateOrderParam(IPerpetual perpetual, LibOrder.OrderParam memory orderParam)
        internal
        view
        returns (bytes32)
    {
        address broker = perpetual.currentBroker(orderParam.trader);
        require(broker == msg.sender, "invalid broker");
        require(orderParam.getOrderVersion() == 2, "unsupported version");
        require(orderParam.getExpiredAt() >= block.timestamp, "order expired");

        bytes32 orderHash = orderParam.getOrderHash(address(perpetual), broker);
        require(orderParam.signature.isValidSignature(orderHash, orderParam.trader), "invalid signature");
        require(filled[orderHash] < orderParam.amount, "fullfilled order");

        return orderHash;
    }

    function claimTradingFee(IPerpetual perpetual, address trader, int256 fee) internal {
        if (fee > 0) {
            perpetual.transferCashBalance(trader, msg.sender, fee.toUint256());
        } else if (fee < 0) {
            perpetual.transferCashBalance(msg.sender, trader, fee.neg().toUint256());
        }
    }

    function cancelOrder(LibOrder.Order memory order) public {
        require(msg.sender == order.trader || msg.sender == order.broker, "invalid caller");

        bytes32 orderHash = order.getOrderHash();
        cancelled[orderHash] = true;

        emit Cancel(orderHash);
    }

    function claimDevFee(
        IPerpetual perpetual,
        address guy,
        uint256 price,
        uint256 openedAmount,
        uint256 closedAmount,
        int256 feeRate
    ) internal {
        if (feeRate == 0) {
            return;
        }
        int256 hard = price.wmul(openedAmount).toInt256().wmul(feeRate);
        int256 soft = price.wmul(closedAmount).toInt256().wmul(feeRate);
        int256 fee = hard.add(soft);
        address devAddress = perpetual.devAddress();
        if (fee > 0) {
            int256 available = perpetual.availableMargin(guy);
            require(available >= hard, "dev margin");
            fee = fee.min(available);
            perpetual.transferCashBalance(guy, devAddress, fee.toUint256());
        } else if (fee < 0) {
            perpetual.transferCashBalance(devAddress, guy, fee.neg().toUint256());
            require(perpetual.isSafe(devAddress), "dev unsafe");
        }
    }

    function claimTakerDevFee(
        IPerpetual perpetual,
        address guy,
        uint256 price,
        uint256 openedAmount,
        uint256 closedAmount
    ) internal {
        int256 rate = perpetual.getGovernance().takerDevFeeRate;
        claimDevFee(perpetual, guy, price, openedAmount, closedAmount, rate);
    }

    function claimMakerDevFee(
        IPerpetual perpetual,
        address guy,
        uint256 price,
        uint256 openedAmount,
        uint256 closedAmount
    ) internal {
        int256 rate = perpetual.getGovernance().makerDevFeeRate;
        claimDevFee(perpetual, guy, price, openedAmount, closedAmount, rate);
    }
}
