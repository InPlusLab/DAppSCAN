pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameters

import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";
import "../lib/LibOrder.sol";
import "../lib/LibTypes.sol";
import "./AMMGovernance.sol";
import "../interface/IPriceFeeder.sol";
import "../interface/IPerpetualProxy.sol";
import "../token/ShareToken.sol";


contract AMM is AMMGovernance {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;
    // SWC-131-Presence of unused variables: L17
    uint256 private constant ONE_WAD_U = 10**18;
    int256 private constant ONE_WAD_S = 10**18;

    // interfaces
    ShareToken private shareToken;
    IPerpetualProxy public perpetualProxy;
    IPriceFeeder public priceFeeder;

    // funding
    LibTypes.FundingState internal fundingState;

    event CreateAMM();
    event UpdateFundingRate(LibTypes.FundingState fundingState);

    modifier onlyBroker() {
        require(perpetualProxy.currentBroker(msg.sender) == authorizedBroker(), "invalid broker");
        _;
    }

    constructor(address _perpetualProxy, address _priceFeeder, address _shareToken) public {
        priceFeeder = IPriceFeeder(_priceFeeder);
        perpetualProxy = IPerpetualProxy(_perpetualProxy);
        shareToken = ShareToken(_shareToken);

        emit CreateAMM();
    }

    // view functions
    function authorizedBroker() internal view returns (address) {
        return address(perpetualProxy);
    }

    function shareTokenAddress() public view returns (address) {
        return address(shareToken);
    }

    function indexPrice() public view returns (uint256 price, uint256 timestamp) {
        (price, timestamp) = priceFeeder.price();
        require(price != 0, "dangerous index price");
    }

    function positionSize() public view returns (uint256) {
        return perpetualProxy.positionSize();
    }

    // note: last* functions (lastFundingState, lastAvailableMargin, lastFairPrice, etc.) are calculated based on
    //       the on-chain fundingState. current* functions are calculated based on the current timestamp

    function lastFundingState() public view returns (LibTypes.FundingState memory) {
        return fundingState;
    }

    function lastAvailableMargin() internal view returns (uint256) {
        IPerpetualProxy.PoolAccount memory pool = perpetualProxy.getPoolAccount();
        return availableMarginFromPoolAccount(pool);
    }

    function lastFairPrice() internal view returns (uint256) {
        IPerpetualProxy.PoolAccount memory pool = perpetualProxy.getPoolAccount();
        return fairPriceFromPoolAccount(pool);
    }

    function lastPremium() internal view returns (int256) {
        IPerpetualProxy.PoolAccount memory pool = perpetualProxy.getPoolAccount();
        return premiumFromPoolAccount(pool);
    }

    function lastEMAPremium() internal view returns (int256) {
        return fundingState.lastEMAPremium;
    }

    function lastMarkPrice() internal view returns (uint256) {
        int256 index = fundingState.lastIndexPrice.toInt256();
        int256 limit = index.wmul(governance.markPremiumLimit);
        int256 p = index.add(lastEMAPremium());
        p = p.min(index.add(limit));
        p = p.max(index.sub(limit));
        return p.max(0).toUint256();
    }

    function lastPremiumRate() internal view returns (int256) {
        int256 index = fundingState.lastIndexPrice.toInt256();
        int256 rate = lastMarkPrice().toInt256();
        rate = rate.sub(index).wdiv(index);
        return rate;
    }

    function lastFundingRate() public view returns (int256) {
        int256 rate = lastPremiumRate();
        return rate.max(governance.fundingDampener).add(rate.min(-governance.fundingDampener));
    }

    // Public functions
    // note: current* functions (currentFundingState, currentAvailableMargin, currentFairPrice, etc.) are calculated based on
    //       the current timestamp. current* functions are calculated based on the on-chain fundingState

    function currentFundingState() public returns (LibTypes.FundingState memory) {
        funding();
        return fundingState;
    }

    function currentAvailableMargin() public returns (uint256) {
        funding();
        return lastAvailableMargin();
    }

    function currentFairPrice() public returns (uint256) {
        funding();
        return lastFairPrice();
    }

    function currentPremium() public returns (int256) {
        funding();
        return lastPremium();
    }

    function currentMarkPrice() public returns (uint256) {
        funding();
        return lastMarkPrice();
    }

    function currentPremiumRate() public returns (int256) {
        funding();
        return lastPremiumRate();
    }

    function currentFundingRate() public returns (int256) {
        funding();
        return lastFundingRate();
    }

    function currentAccumulatedFundingPerContract() public returns (int256) {
        funding();
        return fundingState.accumulatedFundingPerContract;
    }

    function createPool(uint256 amount) public {
        require(perpetualProxy.status() == LibTypes.Status.NORMAL, "wrong perpetual status");
        require(positionSize() == 0, "pool not empty");
        require(amount.mod(perpetualProxy.lotSize()) == 0, "invalid lot size");

        address trader = msg.sender;
        uint256 blockTime = getBlockTimestamp();
        uint256 newIndexPrice;
        uint256 newIndexTimestamp;
        (newIndexPrice, newIndexTimestamp) = indexPrice();

        initFunding(newIndexPrice, blockTime);
        perpetualProxy.transferBalanceIn(trader, newIndexPrice.wmul(amount).mul(2));
        uint256 opened = perpetualProxy.trade(trader, LibTypes.Side.SHORT, newIndexPrice, amount);
        mintShareTokenTo(trader, amount);

        forceFunding(); // x, y changed, so fair price changed. we need funding now
        mustSafe(trader, opened);
    }

    function getBuyPrice(uint256 amount) internal returns (uint256 price) {
        uint256 x;
        uint256 y;
        (x, y) = currentXY();
        require(y != 0 && x != 0, "empty pool");
        return x.wdiv(y.sub(amount));
    }

    function buyFrom(address trader, uint256 amount, uint256 limitPrice, uint256 deadline) private returns (uint256) {
        require(perpetualProxy.status() == LibTypes.Status.NORMAL, "wrong perpetual status");
        require(amount.mod(perpetualProxy.tradingLotSize()) == 0, "invalid trading lot size");

        uint256 price = getBuyPrice(amount);
        require(limitPrice >= price, "price limited");
        require(getBlockTimestamp() <= deadline, "deadline exceeded");
        uint256 opened = perpetualProxy.trade(trader, LibTypes.Side.LONG, price, amount);

        uint256 value = price.wmul(amount);
        uint256 fee = value.wmul(governance.poolFeeRate);
        uint256 devFee = value.wmul(governance.poolDevFeeRate);
        address devAddress = perpetualProxy.devAddress();

        perpetualProxy.transferBalanceIn(trader, fee);
        perpetualProxy.transferBalanceTo(trader, devAddress, devFee);

        forceFunding(); // x, y changed, so fair price changed. we need funding now
        mustSafe(trader, opened);
        return opened;
    }

    function buyFromWhitelisted(address trader, uint256 amount, uint256 limitPrice, uint256 deadline)
        public
        onlyWhitelisted
        returns (uint256)
    {
        return buyFrom(trader, amount, limitPrice, deadline);
    }

    function buy(uint256 amount, uint256 limitPrice, uint256 deadline) public onlyBroker returns (uint256) {
        return buyFrom(msg.sender, amount, limitPrice, deadline);
    }

    function getSellPrice(uint256 amount) internal returns (uint256 price) {
        uint256 x;
        uint256 y;
        (x, y) = currentXY();
        require(y != 0 && x != 0, "empty pool");
        return x.wdiv(y.add(amount));
    }

    function sellFrom(address trader, uint256 amount, uint256 limitPrice, uint256 deadline) private returns (uint256) {
        require(perpetualProxy.status() == LibTypes.Status.NORMAL, "wrong perpetual status");
        require(amount.mod(perpetualProxy.tradingLotSize()) == 0, "invalid trading lot size");

        uint256 price = getSellPrice(amount);
        require(limitPrice <= price, "price limited");
        require(getBlockTimestamp() <= deadline, "deadline exceeded");
        uint256 opened = perpetualProxy.trade(trader, LibTypes.Side.SHORT, price, amount);

        uint256 value = price.wmul(amount);
        uint256 fee = value.wmul(governance.poolFeeRate);
        uint256 devFee = value.wmul(governance.poolDevFeeRate);
        address devAddress = perpetualProxy.devAddress();
        perpetualProxy.transferBalanceIn(trader, fee);
        perpetualProxy.transferBalanceTo(trader, devAddress, devFee);

        forceFunding(); // x, y changed, so fair price changed. we need funding now
        mustSafe(trader, opened);
        return opened;
    }

    function sellFromWhitelisted(address trader, uint256 amount, uint256 limitPrice, uint256 deadline)
        public
        onlyWhitelisted
        returns (uint256)
    {
        return sellFrom(trader, amount, limitPrice, deadline);
    }

    function sell(uint256 amount, uint256 limitPrice, uint256 deadline) public onlyBroker returns (uint256) {
        return sellFrom(msg.sender, amount, limitPrice, deadline);
    }

    // sell amount, pay 2 * amount * price collateral
    function addLiquidity(uint256 amount) public onlyBroker {
        require(perpetualProxy.status() == LibTypes.Status.NORMAL, "wrong perpetual status");
        require(amount.mod(perpetualProxy.lotSize()) == 0, "invalid lot size");

        uint256 oldAvailableMargin;
        uint256 oldPoolPositionSize;
        (oldAvailableMargin, oldPoolPositionSize) = currentXY();
        require(oldPoolPositionSize != 0 && oldAvailableMargin != 0, "empty pool");

        address trader = msg.sender;
        uint256 price = oldAvailableMargin.wdiv(oldPoolPositionSize);

        uint256 collateralAmount = amount.wmul(price).mul(2);
        perpetualProxy.transferBalanceIn(trader, collateralAmount);
        uint256 opened = perpetualProxy.trade(trader, LibTypes.Side.SHORT, price, amount);

        mintShareTokenTo(trader, shareToken.totalSupply().wmul(amount).wdiv(oldPoolPositionSize));

        forceFunding(); // x, y changed, so fair price changed. we need funding now
        mustSafe(trader, opened);
    }

    function removeLiquidity(uint256 shareAmount) public onlyBroker {
        require(perpetualProxy.status() == LibTypes.Status.NORMAL, "wrong perpetual status");

        address trader = msg.sender;
        uint256 oldAvailableMargin;
        uint256 oldPoolPositionSize;
        (oldAvailableMargin, oldPoolPositionSize) = currentXY();
        require(oldPoolPositionSize != 0 && oldAvailableMargin != 0, "empty pool");
        require(shareToken.balanceOf(msg.sender) >= shareAmount, "shareBalance limited");
        uint256 price = oldAvailableMargin.wdiv(oldPoolPositionSize);
        uint256 amount = shareAmount.wmul(oldPoolPositionSize).wdiv(shareToken.totalSupply());
        amount = amount.sub(amount.mod(perpetualProxy.lotSize()));

        perpetualProxy.transferBalanceOut(trader, price.wmul(amount).mul(2));
        burnShareTokenFrom(trader, shareAmount);
        uint256 opened = perpetualProxy.trade(trader, LibTypes.Side.LONG, price, amount);

        forceFunding(); // x, y changed, so fair price changed. we need funding now
        mustSafe(trader, opened);
    }

    function settleShare() public {
        require(perpetualProxy.status() == LibTypes.Status.SETTLED, "wrong perpetual status");

        address trader = msg.sender;
        IPerpetualProxy.PoolAccount memory pool = perpetualProxy.getPoolAccount();
        uint256 total = availableMarginFromPoolAccount(pool);
        uint256 shareAmount = shareToken.balanceOf(trader);
        uint256 balance = shareAmount.wmul(total).wdiv(shareToken.totalSupply());
        perpetualProxy.transferBalanceOut(trader, balance);
        burnShareTokenFrom(trader, shareAmount);
    }

    // this is a composite function of perp.setBroker + perp.deposit + amm.buy
    // composite functions accept amount = 0
    function depositAndBuy(uint256 depositAmount, uint256 tradeAmount, uint256 limitPrice, uint256 deadline) public {
        perpetualProxy.setBrokerFor(msg.sender, authorizedBroker());
        if (depositAmount > 0) {
            perpetualProxy.depositFor(msg.sender, depositAmount);
        }
        if (tradeAmount > 0) {
            buy(tradeAmount, limitPrice, deadline);
        }
    }

    // this is a composite function of perp.setBroker + perp.depositEther + amm.buy
    // composite functions accept amount = 0
    function depositEtherAndBuy(uint256 tradeAmount, uint256 limitPrice, uint256 deadline) public payable {
        perpetualProxy.setBrokerFor(msg.sender, authorizedBroker());
        if (msg.value > 0) {
            perpetualProxy.depositEtherFor.value(msg.value)(msg.sender);
        }
        if (tradeAmount > 0) {
            buy(tradeAmount, limitPrice, deadline);
        }
    }

    // this is a composite function of perp.setBroker + perp.deposit + amm.sell
    // composite functions accept amount = 0
    function depositAndSell(uint256 depositAmount, uint256 tradeAmount, uint256 limitPrice, uint256 deadline) public {
        perpetualProxy.setBrokerFor(msg.sender, authorizedBroker());
        if (depositAmount > 0) {
            perpetualProxy.depositFor(msg.sender, depositAmount);
        }
        if (tradeAmount > 0) {
            sell(tradeAmount, limitPrice, deadline);
        }
    }

    // this is a composite function of perp.setBroker + perp.depositEther + amm.sell
    // composite functions accept amount = 0
    function depositEtherAndSell(uint256 tradeAmount, uint256 limitPrice, uint256 deadline) public payable {
        perpetualProxy.setBrokerFor(msg.sender, authorizedBroker());
        if (msg.value > 0) {
            perpetualProxy.depositEtherFor.value(msg.value)(msg.sender);
        }
        if (tradeAmount > 0) {
            sell(tradeAmount, limitPrice, deadline);
        }
    }

    // this is a composite function of perp.setBroker + amm.buy + perp.withdraw
    // composite functions accept amount = 0
    function buyAndWithdraw(uint256 tradeAmount, uint256 limitPrice, uint256 deadline, uint256 withdrawAmount) public {
        perpetualProxy.setBrokerFor(msg.sender, authorizedBroker());
        if (tradeAmount > 0) {
            buy(tradeAmount, limitPrice, deadline);
        }
        if (withdrawAmount > 0) {
            perpetualProxy.withdrawFor(msg.sender, withdrawAmount);
        }
    }

    // this is a composite function of perp.setBroker + amm.sell + perp.withdraw
    // composite functions accept amount = 0
    function sellAndWithdraw(uint256 tradeAmount, uint256 limitPrice, uint256 deadline, uint256 withdrawAmount) public {
        perpetualProxy.setBrokerFor(msg.sender, authorizedBroker());
        if (tradeAmount > 0) {
            sell(tradeAmount, limitPrice, deadline);
        }
        if (withdrawAmount > 0) {
            perpetualProxy.withdrawFor(msg.sender, withdrawAmount);
        }
    }

    // this is a composite function of perp.deposit + perp.setBroker + amm.addLiquidity
    // composite functions accept amount = 0
    function depositAndAddLiquidity(uint256 depositAmount, uint256 amount) public {
        perpetualProxy.setBrokerFor(msg.sender, authorizedBroker());
        if (depositAmount > 0) {
            perpetualProxy.depositFor(msg.sender, depositAmount);
        }
        if (amount > 0) {
            addLiquidity(amount);
        }
    }

    // this is a composite function of perp.deposit + perp.setBroker + amm.addLiquidity
    // composite functions accept amount = 0
    function depositEtherAndAddLiquidity(uint256 amount) public payable {
        perpetualProxy.setBrokerFor(msg.sender, authorizedBroker());
        if (msg.value > 0) {
            perpetualProxy.depositEtherFor.value(msg.value)(msg.sender);
        }
        if (amount > 0) {
            addLiquidity(amount);
        }
    }

    function updateIndex() public {
        uint256 oldIndexPrice = fundingState.lastIndexPrice;
        forceFunding();
        address devAddress = perpetualProxy.devAddress();
        if (oldIndexPrice != fundingState.lastIndexPrice) {
            perpetualProxy.transferBalanceTo(devAddress, msg.sender, governance.updatePremiumPrize);
            require(perpetualProxy.isSafe(devAddress), "dev unsafe");
        }
    }

    function initFunding(uint256 newIndexPrice, uint256 blockTime) private {
        require(fundingState.lastFundingTime == 0, "initalready initialized");
        fundingState.lastFundingTime = blockTime;
        fundingState.lastIndexPrice = newIndexPrice;
        fundingState.lastPremium = 0;
        fundingState.lastEMAPremium = 0;
    }

    // changing conditions for funding:
    // condition 1: time
    // condition 2: indexPrice
    // condition 3: fairPrice - hand over to forceFunding
    function funding() public {
        uint256 blockTime = getBlockTimestamp();
        uint256 newIndexPrice;
        uint256 newIndexTimestamp;
        (newIndexPrice, newIndexTimestamp) = indexPrice();
        if (
            blockTime != fundingState.lastFundingTime || // condition 1
            newIndexPrice != fundingState.lastIndexPrice || // condition 2, especially when updateIndex and buy/sell are in the same block
            newIndexTimestamp > fundingState.lastFundingTime // condition 2
        ) {
            forceFunding(blockTime, newIndexPrice, newIndexTimestamp);
        }
    }

    // Internal helpers

    // in order to mock the block.timestamp
    function getBlockTimestamp() internal view returns (uint256) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }

    // a gas-optimized version of currentAvailableMargin() + positionSize(). almost all formulas require these two
    function currentXY() internal returns (uint256 x, uint256 y) {
        funding();
        IPerpetualProxy.PoolAccount memory pool = perpetualProxy.getPoolAccount();
        x = availableMarginFromPoolAccount(pool);
        y = pool.positionSize;
    }

    // a gas-optimized version of lastAvailableMargin()
    function availableMarginFromPoolAccount(IPerpetualProxy.PoolAccount memory pool) internal view returns (uint256) {
        int256 available = pool.cashBalance;
        available = available.sub(pool.positionEntryValue.toInt256());
        available = available.sub(
            pool.socialLossPerContract.wmul(pool.positionSize.toInt256()).sub(pool.positionEntrySocialLoss)
        );
        available = available.sub(
            fundingState.accumulatedFundingPerContract.wmul(pool.positionSize.toInt256()).sub(
                pool.positionEntryFundingLoss
            )
        );
        return available.max(0).toUint256();
    }

    // a gas-optimized version of lastFairPrice
    function fairPriceFromPoolAccount(IPerpetualProxy.PoolAccount memory pool) internal view returns (uint256) {
        uint256 y = pool.positionSize;
        require(y > 0, "funding initialization required");
        uint256 x = availableMarginFromPoolAccount(pool);
        return x.wdiv(y);
    }

    // a gas-optimized version of lastPremium
    function premiumFromPoolAccount(IPerpetualProxy.PoolAccount memory pool) internal view returns (int256) {
        int256 p = fairPriceFromPoolAccount(pool).toInt256();
        p = p.sub(fundingState.lastIndexPrice.toInt256());
        return p;
    }

    function mustSafe(address trader, uint256 opened) internal {
        // perpetual.markPrice is a little different from ours
        uint256 perpetualMarkPrice = perpetualProxy.markPrice();
        if (opened > 0) {
            require(perpetualProxy.isIMSafeWithPrice(trader, perpetualMarkPrice), "im unsafe");
        }
        require(perpetualProxy.isSafeWithPrice(trader, perpetualMarkPrice), "sender unsafe");
        require(perpetualProxy.isProxySafeWithPrice(perpetualMarkPrice), "amm unsafe");
    }
    // SWC-104-Unchecked Call Return Value: L500-502
    function mintShareTokenTo(address guy, uint256 amount) internal {
        shareToken.mint(guy, amount);
    }

    function burnShareTokenFrom(address guy, uint256 amount) internal {
        shareToken.burn(guy, amount);
    }

    function forceFunding() internal {
        uint256 blockTime = getBlockTimestamp();
        uint256 newIndexPrice;
        uint256 newIndexTimestamp;
        (newIndexPrice, newIndexTimestamp) = indexPrice();
        forceFunding(blockTime, newIndexPrice, newIndexTimestamp);
    }

    function forceFunding(uint256 blockTime, uint256 newIndexPrice, uint256 newIndexTimestamp) internal {
        if (fundingState.lastFundingTime == 0) {
            // funding initialization required. but in this case, it's safe to just do nothing and return
            return;
        }
        IPerpetualProxy.PoolAccount memory pool = perpetualProxy.getPoolAccount();
        if (pool.positionSize == 0) {
            // empty pool. it's safe to just do nothing and return
            return;
        }

        if (newIndexTimestamp > fundingState.lastFundingTime) {
            // the 1st update
            nextStateWithTimespan(pool, newIndexPrice, newIndexTimestamp);
        }
        // the 2nd update;
        nextStateWithTimespan(pool, newIndexPrice, blockTime);

        emit UpdateFundingRate(fundingState);
    }

    function nextStateWithTimespan(IPerpetualProxy.PoolAccount memory pool, uint256 newIndexPrice, uint256 endTimestamp)
        private
    {
        require(fundingState.lastFundingTime != 0, "funding initialization required");
        require(endTimestamp >= fundingState.lastFundingTime, "we can't go back in time");

        // update ema
        if (fundingState.lastFundingTime != endTimestamp) {
            int256 timeDelta = endTimestamp.sub(fundingState.lastFundingTime).toInt256();
            int256 acc;
            (fundingState.lastEMAPremium, acc) = getAccumulatedFunding(
                timeDelta,
                fundingState.lastEMAPremium,
                fundingState.lastPremium,
                fundingState.lastIndexPrice.toInt256() // ema is according to the old index
            );
            fundingState.accumulatedFundingPerContract = fundingState.accumulatedFundingPerContract.add(
                acc.div(8 * 3600)
            ); // ema is according to the old index
            fundingState.lastFundingTime = endTimestamp;
        }

        // always update
        fundingState.lastIndexPrice = newIndexPrice; // should update before premium()
        fundingState.lastPremium = premiumFromPoolAccount(pool);
    }

    // solve t in emaPremium == y equation
    function timeOnFundingCurve(
        int256 y,
        int256 v0, // lastEMAPremium
        int256 _lastPremium
    )
        internal
        view
        returns (
            int256 t // normal int, not WAD
        )
    {
        require(y != _lastPremium, "no solution 1 on funding curve");
        t = y.sub(_lastPremium);
        t = t.wdiv(v0.sub(_lastPremium));
        require(t > 0, "no solution 2 on funding curve");
        require(t < ONE_WAD_S, "no solution 3 on funding curve");
        t = t.wln();
        t = t.wdiv(emaAlpha2Ln);
        t = t.ceil(ONE_WAD_S) / ONE_WAD_S;
    }

    // sum emaPremium curve between [x, y)
    function integrateOnFundingCurve(
        int256 x, // normal int, not WAD
        int256 y, // normal int, not WAD
        int256 v0, // lastEMAPremium
        int256 _lastPremium
    ) internal view returns (int256 r) {
        require(x <= y, "integrate reversed");
        r = v0.sub(_lastPremium);
        r = r.wmul(emaAlpha2.wpowi(x).sub(emaAlpha2.wpowi(y)));
        r = r.wdiv(governance.emaAlpha);
        r = r.add(_lastPremium.mul(y.sub(x)));
    }

    struct AccumulatedFundingCalculator {
        int256 vLimit;
        int256 vDampener;
        int256 t1; // normal int, not WAD
        int256 t2; // normal int, not WAD
        int256 t3; // normal int, not WAD
        int256 t4; // normal int, not WAD
    }

    function getAccumulatedFunding(
        int256 n, // time span. normal int, not WAD
        int256 v0, // lastEMAPremium
        int256 _lastPremium,
        int256 _lastIndexPrice
    )
        internal
        view
        returns (
            int256 vt, // new LastEMAPremium
            int256 acc
        )
    {
        require(n > 0, "we can't go back in time");
        AccumulatedFundingCalculator memory ctx;
        vt = v0.sub(_lastPremium);
        vt = vt.wmul(emaAlpha2.wpowi(n));
        vt = vt.add(_lastPremium);
        ctx.vLimit = governance.markPremiumLimit.wmul(_lastIndexPrice);
        ctx.vDampener = governance.fundingDampener.wmul(_lastIndexPrice);
        if (v0 <= -ctx.vLimit) {
            // part A
            if (vt <= -ctx.vLimit) {
                acc = (-ctx.vLimit).add(ctx.vDampener).mul(n);
            } else if (vt <= -ctx.vDampener) {
                ctx.t1 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                acc = (-ctx.vLimit).mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, n, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(n));
            } else if (vt <= ctx.vDampener) {
                ctx.t1 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                acc = (-ctx.vLimit).mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(ctx.t2));
            } else if (vt <= ctx.vLimit) {
                ctx.t1 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                acc = (-ctx.vLimit).mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(ctx.t2.sub(n).add(ctx.t3)));
            } else {
                ctx.t1 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                acc = (-ctx.vLimit).mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium));
                acc = acc.add(ctx.vLimit.mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(ctx.t2.sub(n).add(ctx.t3)));
            }
        } else if (v0 <= -ctx.vDampener) {
            // part B
            if (vt <= -ctx.vLimit) {
                ctx.t4 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t4, v0, _lastPremium);
                acc = acc.add((-ctx.vLimit).mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(n));
            } else if (vt <= -ctx.vDampener) {
                acc = integrateOnFundingCurve(0, n, v0, _lastPremium);
                acc = acc.add(ctx.vDampener.mul(n));
            } else if (vt <= ctx.vDampener) {
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.add(ctx.vDampener.mul(ctx.t2));
            } else if (vt <= ctx.vLimit) {
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.add(integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(ctx.t2.sub(n).add(ctx.t3)));
            } else {
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.add(integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium));
                acc = acc.add(ctx.vLimit.mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(ctx.t2.sub(n).add(ctx.t3)));
            }
        } else if (v0 <= ctx.vDampener) {
            // part C
            if (vt <= -ctx.vLimit) {
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium);
                acc = acc.add((-ctx.vLimit).mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3)));
            } else if (vt <= -ctx.vDampener) {
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium);
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3)));
            } else if (vt <= ctx.vDampener) {
                acc = 0;
            } else if (vt <= ctx.vLimit) {
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium);
                acc = acc.sub(ctx.vDampener.mul(n.sub(ctx.t3)));
            } else {
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium);
                acc = acc.add(ctx.vLimit.mul(n.sub(ctx.t4)));
                acc = acc.sub(ctx.vDampener.mul(n.sub(ctx.t3)));
            }
        } else if (v0 <= ctx.vLimit) {
            // part D
            if (vt <= -ctx.vLimit) {
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.add(integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium));
                acc = acc.add((-ctx.vLimit).mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3).sub(ctx.t2)));
            } else if (vt <= -ctx.vDampener) {
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.add(integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3).sub(ctx.t2)));
            } else if (vt <= ctx.vDampener) {
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.sub(ctx.vDampener.mul(ctx.t2));
            } else if (vt <= ctx.vLimit) {
                acc = integrateOnFundingCurve(0, n, v0, _lastPremium);
                acc = acc.sub(ctx.vDampener.mul(n));
            } else {
                ctx.t4 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t4, v0, _lastPremium);
                acc = acc.add(ctx.vLimit.mul(n.sub(ctx.t4)));
                acc = acc.sub(ctx.vDampener.mul(n));
            }
        } else {
            // part E
            if (vt <= -ctx.vLimit) {
                ctx.t1 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                acc = ctx.vLimit.mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium));
                acc = acc.add((-ctx.vLimit).mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3).sub(ctx.t2)));
            } else if (vt <= -ctx.vDampener) {
                ctx.t1 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                acc = ctx.vLimit.mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3).sub(ctx.t2)));
            } else if (vt <= ctx.vDampener) {
                ctx.t1 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                acc = ctx.vLimit.mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(-ctx.t2));
            } else if (vt <= ctx.vLimit) {
                ctx.t1 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                acc = ctx.vLimit.mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, n, v0, _lastPremium));
                acc = acc.sub(ctx.vDampener.mul(n));
            } else {
                acc = ctx.vLimit.sub(ctx.vDampener).mul(n);
            }
        }
    } // getAccumulatedFunding
}
