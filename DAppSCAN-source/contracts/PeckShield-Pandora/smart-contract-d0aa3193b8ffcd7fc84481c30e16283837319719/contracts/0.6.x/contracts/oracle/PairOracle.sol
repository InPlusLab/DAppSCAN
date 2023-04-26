// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";

import "../libraries/UQ112x112.sol";
import "../libraries/FixedPoint.sol";
import "../interfaces/IPairOracle.sol";
import "../interfaces/ISwapPair.sol";
import "./Operator.sol";

contract PairOracle is Operator, IPairOracle, Initializable {
    using FixedPoint for *;
    using SafeMath for uint256;

    uint256 public PERIOD = 600; // 10-minute TWAP (time-weighted average price)

    ISwapPair public pair;
    address public token0;
    address public token1;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public blockTimestampLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    function initialize(address pairAddress) external onlyOwner initializer {
        ISwapPair _pair = ISwapPair(pairAddress);
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // Fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // Fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "vSwapPairOracle: NO_RESERVES"); // Ensure that there's liquidity in the pair
    }

    function setPeriod(uint256 _period) external onlyOperator {
        PERIOD = _period;
    }

    function update() external override {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // Overflow is desired

        // Ensure that at least one full period has passed since the last update
        require(timeElapsed >= PERIOD, "vSwapPairOracle: PERIOD_NOT_ELAPSED");

        // Overflow is desired, casting never truncates
        // Cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));
        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    // Note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint256 amountIn) external view override returns (uint256 amountOut) {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == token1, "vSwapPairOracle: INVALID_TOKEN");
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }

    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2**32);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(address _pair)
    internal
    view
    returns (
        uint256 price0Cumulative,
        uint256 price1Cumulative,
        uint32 blockTimestamp
    )
    {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = ISwapPair(_pair).price0CumulativeLast();
        price1Cumulative = ISwapPair(_pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 _blockTimestampLast) = ISwapPair(pair).getReserves();
        if (_blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            price0Cumulative += uint256(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // counterfactual
            price1Cumulative += uint256(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }
}
