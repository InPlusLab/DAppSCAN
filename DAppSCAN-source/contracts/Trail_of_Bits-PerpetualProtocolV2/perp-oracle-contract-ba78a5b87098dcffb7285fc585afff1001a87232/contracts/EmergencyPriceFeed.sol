// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { FixedPoint96 } from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { IPriceFeed } from "./interface/IPriceFeed.sol";
import { BlockContext } from "./base/BlockContext.sol";

contract EmergencyPriceFeed is IPriceFeed, BlockContext {
    using Address for address;

    //
    // STATE
    //

    address public pool;

    //
    // EXTERNAL NON-VIEW
    //

    constructor(address poolArg) {
        // EPF_EANC: pool address is not contract
        require(address(poolArg).isContract(), "EPF_EANC");

        pool = poolArg;
    }

    //
    // EXTERNAL VIEW
    //

    function getPrice(uint256 interval) external view override returns (uint256) {
        uint256 markTwapX96 = _formatSqrtPriceX96ToPriceX96(_getSqrtMarkTwapX96(_toUint32(interval)));
        return _formatX96ToX10_18(markTwapX96);
    }

    //
    // EXTERNAL PURE
    //

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    /// @dev if twapInterval < 10 (should be less than 1 block), return mark price without twap directly,
    ///      as twapInterval is too short and makes getting twap over such a short period meaningless
    function _getSqrtMarkTwapX96(uint32 twapInterval) internal view returns (uint160) {
        // return the current price as twapInterval is too short/ meaningless
        if (twapInterval < 10) {
            (uint160 sqrtMarkPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();
            return sqrtMarkPrice;
        }
        uint32[] memory secondsAgos = new uint32[](2);

        // solhint-disable-next-line not-rely-on-time
        secondsAgos[0] = twapInterval;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgos);

        // tick(imprecise as it's an integer) to price
        return TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / twapInterval));
    }

    /**
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     */
    function _toUint32(uint256 value) internal pure returns (uint32 returnValue) {
        require(((returnValue = uint32(value)) == value), "SafeCast: value doesn't fit in 32 bits");
    }

    function _formatSqrtPriceX96ToPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    function _formatX96ToX10_18(uint256 valueX96) internal pure returns (uint256) {
        return FullMath.mulDiv(valueX96, 1e18, FixedPoint96.Q96);
    }
}
