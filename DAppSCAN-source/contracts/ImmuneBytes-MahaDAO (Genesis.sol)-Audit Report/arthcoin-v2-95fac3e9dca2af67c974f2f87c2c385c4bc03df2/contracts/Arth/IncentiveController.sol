// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {SafeCast} from '../utils/math/SafeCast.sol';
import {SignedSafeMath} from '../utils/math/SignedSafeMath.sol';

import {IARTH} from './IARTH.sol';
import {Math} from '../utils/math/Math.sol';
import {SafeMath} from '../utils/math/SafeMath.sol';
import {IIncentiveController} from './IIncentive.sol';
import {AccessControl} from '../access/AccessControl.sol';
import {IChainlinkOracle} from '../Oracle/IChainlinkOracle.sol';
import {IUniswapPairOracle} from '../Oracle/IUniswapPairOracle.sol';
import {IUniswapV2Pair} from '../Uniswap/Interfaces/IUniswapV2Pair.sol';

contract IncentiveController is AccessControl, IIncentiveController {
    using SafeCast for int256;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    /**
     * Data structures.
     */

    struct TimeWeightInfo {
        uint32 blockNo;
        uint32 weight;
        uint32 growthRate;
        bool active;
    }

    /**
     * State varaibles.
     */

    IARTH public ARTH;
    IChainlinkOracle public ethGMUPricer;
    IUniswapPairOracle public arthETHOracle;
    TimeWeightInfo private _timeWeightInfo;

    address public uniswapPairAddress;
    uint256 public targetPrice = 1000000; // i.e 1e6.

    /// @notice the granularity of the time weight and growth rate
    uint32 public constant TIME_WEIGHT_GRANULARITY = 100_000;

    uint8 private _ethGMUPricerDecimals;
    uint256 private constant _PRICE_PRECISION = 1e6;

    mapping(address => bool) private _exempt;

    /**
     * Modifiers.
     */

    modifier onlyARTH() {
        require(
            _msgSender() == address(ARTH),
            "IncentiveController: FORBIDDEN"
        );
        _;
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            'Controller: FORBIDDEN'
        );
        _;
    }

    /**
     * Constructor.
     */

    constructor(
        IARTH ARTH_,
        address arthETHOracle_,
        address ethGMUPricer_,
        address uniswapPairAddress_
    ) {
        ARTH = ARTH_;
        uniswapPairAddress = uniswapPairAddress_;

        ethGMUPricer = IChainlinkOracle(ethGMUPricer_);
        _ethGMUPricerDecimals = ethGMUPricer.getDecimals();
        arthETHOracle = IUniswapPairOracle(arthETHOracle_);

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function getReserves() public view returns (uint256, uint256) {
        address token0 = IUniswapV2Pair(uniswapPairAddress).token0();
        (uint256 reserve0, uint256 reserve1, ) =
            IUniswapV2Pair(uniswapPairAddress).getReserves();

        (uint256 arthReserves, uint256 tokenReserves) =
            address(ARTH) == token0
                ? (reserve0, reserve1)
                : (reserve1, reserve0);

        return (arthReserves, tokenReserves);
    }

    function _getUniswapPrice() internal view returns (uint256) {
        (uint256 reserveARTH, uint256 reserveOther) = getReserves();
        return reserveARTH.mul(_PRICE_PRECISION).div(reserveOther);
    }

    function getCurrentArthPrice() internal view returns (uint256) {
        // Get the ETH/GMU price first, and cut it down to 1e6 precision.
        uint256 ethToGMUPrice =
            uint256(ethGMUPricer.getLatestPrice()).mul(_PRICE_PRECISION).div(
                uint256(10)**_ethGMUPricerDecimals
            );

        uint256 arthEthPrice = _getUniswapPrice();
        return ethToGMUPrice.mul(arthEthPrice).div(_PRICE_PRECISION);
    }

    function isExemptAddress(address account) public view returns (bool) {
        return _exempt[account];
    }

    function updateOracle() public {
        try arthETHOracle.update() {} catch {}
    }

    function _isPair(address account) internal view returns (bool) {
        return address(uniswapPairAddress) == account;
    }

    function getGrowthRate() public view returns (uint32) {
        return _timeWeightInfo.growthRate;
    }

    function isTimeWeightActive() public view returns (bool) {
        return _timeWeightInfo.active;
    }

    function getTimeWeight() public view returns (uint32) {
        TimeWeightInfo memory tw = _timeWeightInfo;
        if (!tw.active) return 0;
        uint32 blockDelta = uint32(uint256(block.number).sub(tw.blockNo));
        return uint32(uint256(tw.weight).add(blockDelta * tw.growthRate));
    }

    function _setTimeWeight(
        uint32 weight,
        uint32 growthRate,
        bool active
    ) internal {
        uint32 blockNo = uint32(block.number);

        _timeWeightInfo = TimeWeightInfo(blockNo, weight, growthRate, active);
    }

    function setTimeWeightGrowth(uint32 growthRate) public onlyAdmin {
        TimeWeightInfo memory tw = _timeWeightInfo;

        _timeWeightInfo = TimeWeightInfo(
            tw.blockNo,
            tw.weight,
            growthRate,
            tw.active
        );
    }

    function setExemptAddress(address account, bool isExempt) public onlyAdmin {
        _exempt[account] = isExempt;
    }

    function getSellPenalty(uint256 amount)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 initialDeviation, uint256 finalDeviation) =
            _getPriceDeviations(int256(amount));
        (uint256 reserveARTH, uint256 reserveOther) = getReserves();

        // If trafe ends above peg, it was always above peg and no penalty needed.
        if (finalDeviation == 0) {
            return (0, initialDeviation, finalDeviation);
        }

        uint256 incentivizedAmount = amount;
        // if trade started above but ended below, only penalize amount going below peg
        if (initialDeviation == 0) {
            uint256 amountToPeg =
                _getAmountToPegARTH(reserveARTH, reserveOther);

            incentivizedAmount = amount.sub(
                amountToPeg,
                'UniswapIncentive: Underflow'
            );
        }

        uint256 multiplier =
            _calculateIntegratedSellPenaltyMultiplier(
                initialDeviation,
                finalDeviation
            );

        uint256 penalty = multiplier.mul(incentivizedAmount);

        return (penalty, initialDeviation, finalDeviation);
    }

    function _incentivizeSell(address target, uint256 amount)
        internal
    // ifBurnerSelf
    {
        if (isExemptAddress(target)) {
            return;
        }

        uint32 weight = getTimeWeight();
        (uint256 penalty, uint256 initialDeviation, uint256 finalDeviation) =
            getSellPenalty(amount);

        _updateTimeWeight(weight, finalDeviation, initialDeviation);

        if (penalty != 0) {
            require(
                penalty < amount,
                'UniswapIncentive: Burn exceeds trade size'
            );

            ARTH.poolBurnFrom(address(uniswapPairAddress), penalty);
        }
    }

    function incentivize(
        address sender,
        address receiver,
        address,
        uint256 amountIn
    ) public override onlyARTH {
        require(sender != receiver, 'UniswapIncentive: cannot send self');
        updateOracle();

        if (_isPair(sender)) {
            _incentivizeBuy(receiver, amountIn);
        }

        if (_isPair(receiver)) {
            _incentivizeSell(sender, amountIn);
        }
    }

    function _updateTimeWeight(
        uint32 currentWeight,
        uint256 finalDeviation,
        uint256 initialDeviation
    ) internal {
        // Reset when trade ends above peg.
        if (finalDeviation == 0) {
            _setTimeWeight(0, getGrowthRate(), false);
            return;
        }

        // When trade starts above peg but ends below, activate time weight.
        if (initialDeviation == 0) {
            _setTimeWeight(0, getGrowthRate(), true);
            return;
        }

        // When trade starts and ends below the peg, update the values.
        uint256 updatedWeight = uint256(currentWeight);

        // Partial buy should update time weight.
        if (initialDeviation > finalDeviation) {
            uint256 remainingRatio =
                finalDeviation.mul(_PRICE_PRECISION).div(initialDeviation).div(
                    _PRICE_PRECISION
                );

            updatedWeight = remainingRatio.mul(uint256(currentWeight));
        }

        // Cap incentive at max penalty.
        uint256 maxWeight =
            finalDeviation.mul(100).mul(uint256(TIME_WEIGHT_GRANULARITY)); // m^2*100 (sell) = t*m (buy)

        updatedWeight = Math.min(updatedWeight, maxWeight);

        _setTimeWeight(uint32(updatedWeight), getGrowthRate(), true);
    }

    function _incentivizeBuy(address target, uint256 amountIn)
        internal
    // ifMinterSelf
    {
        if (isExemptAddress(target)) {
            return;
        }

        (
            uint32 weight,
            uint256 incentive,
            uint256 finalDeviation,
            uint256 initialDeviation
        ) = getBuyIncentive(amountIn);

        _updateTimeWeight(weight, finalDeviation, initialDeviation);

        if (incentive != 0) ARTH.poolMint(target, incentive); // poolMint? or create seperate mint for controller?
    }

    function _getFinalPrice(
        int256 amountARTH,
        uint256 reserveARTH,
        uint256 reserveOther
    ) internal pure returns (uint256) {
        uint256 k = reserveARTH.mul(reserveOther);

        // Buys already have fee factored in on uniswap's other token side.
        int256 amountARTHWithFee =
            amountARTH > 0 ? amountARTH.mul(997).div(1000) : amountARTH;

        int256 reserveARTHSignedFormat = int256(reserveARTH);
        uint256 adjustedReserveARTH =
            uint256(reserveARTHSignedFormat.add(amountARTHWithFee));
        uint256 adjustedReserveOther = k.div(adjustedReserveARTH);

        return
            adjustedReserveARTH.mul(_PRICE_PRECISION).div(adjustedReserveOther);
    }

    function _deviationBelowPeg(uint256 price) internal view returns (uint256) {
        if (price > targetPrice) return 0;

        return
            targetPrice.sub(price).mul(_PRICE_PRECISION).div(targetPrice).div(
                _PRICE_PRECISION
            );
    }

    function _getPriceDeviations(int256 amountIn)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 price = getCurrentArthPrice();
        (uint256 reservesARTH, uint256 reservesQuote) = getReserves();

        uint256 initialDeviation = _deviationBelowPeg(price);

        uint256 finalPrice =
            _getFinalPrice(amountIn, reservesARTH, reservesQuote);
        uint256 finalDeviation = _deviationBelowPeg(finalPrice);

        return (initialDeviation, finalDeviation);
    }

    function _getAmountToPegARTH(uint256 arthReserves, uint256 tokenReserves)
        internal
        view
        returns (uint256)
    {
        return _getAmountToPeg(arthReserves, tokenReserves);
    }

    function _getAmountToPeg(uint256 reserveTarget, uint256 reserveOther)
        internal
        view
        returns (uint256)
    {
        uint256 missingDecimals = uint256(ARTH.decimals()).sub(6);
        uint256 radicand =
            targetPrice.mul(reserveTarget).mul(reserveOther).mul(
                10**missingDecimals
            );

        uint256 root = Math.sqrt(radicand);

        if (root > reserveTarget)
            return root.sub(reserveTarget).mul(1000).div(997);

        return reserveTarget.sub(root).mul(1000).div(997);
    }

    function _calculateSellPenaltyMultiplier(uint256 deviation)
        internal
        pure
        returns (uint256)
    {
        uint256 multiplier = deviation.mul(deviation).mul(100);
        if (multiplier > 1e18) return 1e18;

        return multiplier;
    }

    function _sellPenaltyBound(uint256 deviation)
        internal
        pure
        returns (uint256)
    {
        return (deviation**3).mul(33);
    }

    function _calculateIntegratedSellPenaltyMultiplier(
        uint256 initialDeviation,
        uint256 finalDeviation
    ) internal pure returns (uint256) {
        if (initialDeviation == finalDeviation)
            return _calculateSellPenaltyMultiplier(initialDeviation);

        uint256 numerator =
            _sellPenaltyBound(finalDeviation).sub(
                _sellPenaltyBound(initialDeviation)
            );
        uint256 denominator = finalDeviation.sub(initialDeviation);

        uint256 multiplier = numerator.div(denominator);
        if (multiplier > 1e18) return 1e18;

        return multiplier;
    }

    function _calculateBuyIncentiveMultiplier(
        uint32 weight,
        uint256 finalDeviation,
        uint256 initialDeviation
    ) internal pure returns (uint256) {
        uint256 correspondingPenalty =
            _calculateIntegratedSellPenaltyMultiplier(
                initialDeviation,
                finalDeviation
            );

        uint256 buyMultiplier =
            initialDeviation.mul(uint256(weight)).div(
                uint256(TIME_WEIGHT_GRANULARITY)
            );

        if (correspondingPenalty < buyMultiplier) return correspondingPenalty;

        return buyMultiplier;
    }

    function getBuyIncentive(uint256 amount)
        public
        view
        returns (
            uint32,
            uint256,
            uint256,
            uint256
        )
    {
        uint32 weight = getTimeWeight();

        int256 amountSignedFormat = int256(amount);
        (uint256 initialDeviation, uint256 finalDeviation) =
            _getPriceDeviations(amountSignedFormat.mul(-1));
        (uint256 reserveARTH, uint256 reserveOther) = getReserves();

        // Buy started above peg.
        if (initialDeviation == 0)
            return (weight, 0, finalDeviation, initialDeviation);

        uint256 incentivizedAmount = amount;
        // If buy ends above peg, only incentivize amount to peg.
        if (finalDeviation == 0)
            incentivizedAmount = _getAmountToPegARTH(reserveARTH, reserveOther);

        uint256 multiplier =
            _calculateBuyIncentiveMultiplier(
                weight,
                finalDeviation,
                initialDeviation
            );

        uint256 incentive = multiplier.mul(incentivizedAmount);

        return (weight, incentive, finalDeviation, initialDeviation);
    }
}
