// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IERC20} from '../ERC20/IERC20.sol';
import {IWETH} from '@uniswap/v2-periphery/contracts/interfaces/IWETH.sol';
import {
    TransferHelper
} from '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import {SafeMath} from '../utils/math/SafeMath.sol';
import {IUniswapSwapRouter} from './IUniswapSwapRouter.sol';
import {UniswapV2Library} from '../Uniswap/UniswapV2Library.sol';
import {IUniswapV2Pair} from '../Uniswap/Interfaces/IUniswapV2Pair.sol';
import {IUniswapV2Factory} from '../Uniswap/Interfaces/IUniswapV2Factory.sol';

/**
 * @title  A Uniswap Router for pairs involving ARTH.
 * @author MahaDAO.
 */
contract UniswapSwapRouter is IUniswapSwapRouter {
    using SafeMath for uint256;

    /**
     * State variables.
     */

    IWETH public immutable WETH;
    IUniswapV2Factory public immutable FACTORY;

    address public arthAddress;

    /**
     * Modifiers.
     */

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'UniswapSwapRouter: EXPIRED');
        _;
    }

    modifier ensureIsPair(address token) {
        require(
            FACTORY.getPair(token, arthAddress) != address(0),
            'UniswapSwapRouter: invalid pair'
        );
        _;
    }

    /**
     * Constructor.
     */
    constructor(
        IWETH weth_,
        address arthAddress_,
        IUniswapV2Factory FACTORY_
    ) {
        WETH = weth_;
        FACTORY = FACTORY_;
        arthAddress = arthAddress_;
    }

    /**
     * External.
     */

    receive() external payable {
        // Only accept ETH via fallback from the WETH contract.
        assert(msg.sender == address(WETH));
    }

    /**
     * @notice             Buy ARTH for ETH with some protections.
     * @param minReward    Minimum mint reward for purchasing.
     * @param amountOutMin Minimum ARTH received.
     * @param to           Address to send ARTH.
     * @param deadline     Block timestamp after which trade is invalid.
     */
    function buyARTHForETH(
        uint256 minReward,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256 amountOut) {
        (uint256 reservesETH, uint256 reservesOther, bool isWETHPairToken0) =
            _getReserves(address(WETH));

        amountOut = UniswapV2Library.getAmountOut(
            msg.value,
            reservesETH,
            reservesOther
        );
        require(
            amountOut >= amountOutMin,
            'UniswapSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );

        IUniswapV2Pair pair =
            IUniswapV2Pair(FACTORY.getPair(address(WETH), arthAddress));
        require(address(pair) != address(0), 'UniswapSwapRouter: INVALID_PAIR');

        // Convert sent ETH to wrapped ETH and assert successful transfer to pair.
        WETH.deposit{value: msg.value}();
        assert(WETH.transfer(address(pair), msg.value));

        address arth = isWETHPairToken0 ? pair.token1() : pair.token0();
        // Check ARTH balance of recipient before to compare against.
        uint256 arthBalanceBefore = IERC20(arth).balanceOf(to);

        (uint256 amount0Out, uint256 amount1Out) =
            isWETHPairToken0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

        pair.swap(amount0Out, amount1Out, to, new bytes(0));

        // Check that ARTH recipient got at least minReward on top of trade amount.
        uint256 arthBalanceAfter = IERC20(arth).balanceOf(to);
        uint256 reward = arthBalanceAfter.sub(arthBalanceBefore).sub(amountOut);
        require(reward >= minReward, 'UniswapSwapRouter: Not enough reward');

        return amountOut;
    }

    /**
     * @notice             Buy ARTH for ERC20 with some protections.
     * @param token        The ERC20 token address to sell.
     * @param minReward    Minimum mint reward for purchasing.
     * @param amountOutMin Minimum ARTH received.
     * @param to           Address to send ARTH.
     * @param deadline     Block timestamp after which trade is invalid.
     */
    function buyARTHForERC20(
        address token,
        uint256 amountIn,
        uint256 minReward,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 amountOut) {
        (uint256 reservesToken, uint256 reservesOther, bool isTokenPairToken0) =
            _getReserves(token);

        amountOut = UniswapV2Library.getAmountOut(
            amountIn,
            reservesToken,
            reservesOther
        );
        require(
            amountOut >= amountOutMin,
            'UniswapSwapRouter: Insufficient output amount'
        );

        IUniswapV2Pair pair =
            IUniswapV2Pair(FACTORY.getPair(token, arthAddress));
        require(address(pair) != address(0), 'UniswapSwapRouter: INVALID_PAIR');

        require(
            IERC20(token).balanceOf(msg.sender) >= amountIn,
            'UniswapSwapRouter: amount < required'
        );
        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(pair),
            amountIn
        );

        address arth = isTokenPairToken0 ? pair.token1() : pair.token0();
        // Check ARTH balance of recipient before to compare against.
        uint256 arthBalanceBefore = IERC20(arth).balanceOf(to);

        (uint256 amount0Out, uint256 amount1Out) =
            isTokenPairToken0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

        pair.swap(amount0Out, amount1Out, to, new bytes(0));

        // Check that ARTH recipient got at least minReward on top of trade amount.
        uint256 arthBalanceAfter = IERC20(arth).balanceOf(to);
        uint256 reward = arthBalanceAfter.sub(arthBalanceBefore).sub(amountOut);
        require(reward >= minReward, 'UniswapSwapRouter: Not enough reward');

        return amountOut;
    }

    /**
     * @notice             Sell ARTH for ETH with some protections.
     * @param maxPenalty   Maximum ARTH burn for purchasing.
     * @param amountIn     Amount of ARTH to sell.
     * @param amountOutMin Minimum ETH received.
     * @param to           Address to send ETH.
     * @param deadline     Block timestamp after which trade is invalid.
     */
    function sellARTHForETH(
        uint256 maxPenalty,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 amountOut) {
        (uint256 reservesETH, uint256 reservesOther, bool isWETHPairToken0) =
            _getReserves(address(WETH));

        IUniswapV2Pair pair =
            IUniswapV2Pair(FACTORY.getPair(address(WETH), arthAddress));
        require(address(pair) != address(0), 'UniswapSwapRouter: INVALID_PAIR');

        address arth = isWETHPairToken0 ? pair.token1() : pair.token0();

        require(
            IERC20(arth).balanceOf(msg.sender) >= amountIn,
            'UniswapSwapRouter: balance < required'
        );
        IERC20(arth).transferFrom(msg.sender, address(pair), amountIn);

        // Figure out how much the PAIR actually received net of ARTH burn.
        uint256 effectiveAmountIn =
            IERC20(arth).balanceOf(address(pair)).sub(reservesOther);

        // Check that burned fee-on-transfer is not more than the maxPenalty
        if (effectiveAmountIn < amountIn) {
            uint256 penalty = amountIn - effectiveAmountIn;
            require(
                penalty <= maxPenalty,
                'UniswapSwapRouter: Penalty too high'
            );
        }

        amountOut = UniswapV2Library.getAmountOut(
            effectiveAmountIn,
            reservesOther,
            reservesETH
        );
        require(
            amountOut >= amountOutMin,
            'UniswapSwapRouter: Insufficient output amount'
        );

        (uint256 amount0Out, uint256 amount1Out) =
            isWETHPairToken0
                ? (amountOut, uint256(0))
                : (uint256(0), amountOut);

        pair.swap(amount0Out, amount1Out, address(this), new bytes(0));

        IWETH(WETH).withdraw(amountOut);

        TransferHelper.safeTransferETH(to, amountOut);
        return amountOut;
    }

    /**
     * @notice             Sell ARTH for ETH with some protections.
     * @param token        The token which is to be bought.
     * @param maxPenalty   Maximum ARTH burn for purchasing.
     * @param amountIn     Amount of ARTH to sell.
     * @param amountOutMin Minimum ETH received.
     * @param to           Address to send ETH.
     * @param deadline     Block timestamp after which trade is invalid.
     */
    function sellARTHForERC20(
        address token,
        uint256 maxPenalty,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 amountOut) {
        (uint256 reservesToken, uint256 reservesOther, bool isTokenPairToken0) =
            _getReserves(token);

        IUniswapV2Pair pair =
            IUniswapV2Pair(FACTORY.getPair(token, arthAddress));
        require(address(pair) != address(0), 'UniswapSwapRouter: INVALID_PAIR');

        address arth = isTokenPairToken0 ? pair.token1() : pair.token0();

        require(
            IERC20(arth).balanceOf(msg.sender) >= amountIn,
            'UniswapSwapRouter: balance < required'
        );
        IERC20(arth).transferFrom(msg.sender, address(pair), amountIn);

        // Figure out how much the PAIR actually received net of ARTH burn.
        uint256 effectiveAmountIn =
            IERC20(arth).balanceOf(address(pair)).sub(reservesOther);

        // Check that burned fee-on-transfer is not more than the maxPenalty
        if (effectiveAmountIn < amountIn) {
            uint256 penalty = amountIn - effectiveAmountIn;
            require(
                penalty <= maxPenalty,
                'UniswapSwapRouter: Penalty too high'
            );
        }

        amountOut = UniswapV2Library.getAmountOut(
            effectiveAmountIn,
            reservesOther,
            reservesToken
        );
        require(
            amountOut >= amountOutMin,
            'UniswapSwapRouter: Insufficient output amount'
        );

        (uint256 amount0Out, uint256 amount1Out) =
            isTokenPairToken0
                ? (amountOut, uint256(0))
                : (uint256(0), amountOut);

        pair.swap(amount0Out, amount1Out, to, new bytes(0));

        return amountOut;
    }

    /**
     * Internal.
     */

    function _getReserves(address token)
        internal
        view
        returns (
            uint256 reservesToken,
            uint256 reservesOther,
            bool isTokenPairToken0
        )
    {
        IUniswapV2Pair pair =
            IUniswapV2Pair(FACTORY.getPair(token, arthAddress));
        require(address(pair) != address(0), 'UniswapSwapRouter: INVALID_PAIR');

        (uint256 reserves0, uint256 reserves1, ) = pair.getReserves();
        isTokenPairToken0 = pair.token0() == token;

        return
            isTokenPairToken0
                ? (reserves0, reserves1, isTokenPairToken0)
                : (reserves1, reserves0, isTokenPairToken0);
    }
}
