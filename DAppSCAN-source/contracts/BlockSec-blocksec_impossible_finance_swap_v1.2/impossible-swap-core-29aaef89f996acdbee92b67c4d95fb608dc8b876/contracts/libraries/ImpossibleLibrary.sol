/// SPDX-License-Identifier: GPL-3
pragma solidity >=0.5.0;

import '../interfaces/IImpossiblePair.sol';
import '../interfaces/IERC20.sol';

import './SafeMath.sol';
import './Math.sol';

library ImpossibleLibrary {
    using SafeMath for uint256;

    /**
     @notice Sorts tokens in ascending order
     @param tokenA The address of token A
     @param tokenB The address of token B
     @return token0 The address of token 0 (lexicographically smaller than addr of token 1)
     @return token1 The address of token 1 (lexicographically larger than addr of token 0)
    */
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'ImpossibleLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ImpossibleLibrary: ZERO_ADDRESS');
    }

    /**
     @notice Computes the pair contract create2 address deterministically
     @param factory The address of the token factory (pair contract deployer)
     @param tokenA The address of token A
     @param tokenB The address of token B
     @return pair The address of the pair containing token A and B
    */
    function pairFor(
        address factory,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encodePacked(token0, token1)),
                        hex'cd6a00bb24f01736b4641e428f720a1dee69319ca269cf3de70ea2d1adfa99cf' // init code hash
                    )
                )
            )
        );
    }

    /**
     @notice Obtains the token reserves in the pair contract
     @param factory The address of the token factory (pair contract deployer)
     @param tokenA The address of token A
     @param tokenB The address of token B
     @return reserveA The amount of token A in reserves
     @return reserveB The amount of token B in reserves
     @return pair The address of the pair containing token A and B
    */
    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    )
        internal
        view
        returns (
            uint256 reserveA,
            uint256 reserveB,
            address pair
        )
    {
        (address token0, ) = sortTokens(tokenA, tokenB);
        pair = pairFor(factory, tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1) = IImpossiblePair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /**
     @notice Quote returns amountB based on some amountA, in the ratio of reserveA:reserveB
     @param amountA The amount of token A
     @param reserveA The amount of reserveA
     @param reserveB The amount of reserveB
     @return amountB The amount of token B that matches amount A in the ratio of reserves
    */
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, 'ImpossibleLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'ImpossibleLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    /**
     @notice Internal helper function for calculating artificial liquidity
     @dev More details on math at: https://docs.impossible.finance/impossible-swap/swap-math
     @param _boost The boost variable on the correct side for the pair contract
     @param _sqrtK The sqrt of the invariant variable K in xybk formula
     @return uint256 The artificial liquidity term
    */
    function calcArtiLiquidityTerm(uint256 _boost, uint256 _sqrtK) internal pure returns (uint256) {
        return (_boost - 1).mul(_sqrtK);
    }

    /**
     @notice Quotes maximum output given exact input amount of tokens and addresses of tokens in pair
     @dev The library function considers custom swap fees/invariants/asymmetric tuning of pairs
     @dev However, library function doesn't consider limits created by hardstops
     @param amountIn The input amount of token A
     @param tokenIn The address of input token
     @param tokenOut The address of output token
     @param factory The address of the factory contract
     @return amountOut The maximum output amount of token B for a valid swap
    */
    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        address factory
    ) internal view returns (uint256 amountOut) {
        require(amountIn > 0, 'ImpossibleLibrary: INSUFFICIENT_INPUT_AMOUNT');
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 amountInPostFee;
        address pair;
        bool isMatch;
        {
            // Avoid stack too deep
            (address token0, ) = sortTokens(tokenIn, tokenOut);
            isMatch = tokenIn == token0;
            (reserveIn, reserveOut, pair) = getReserves(factory, tokenIn, tokenOut);
            require(reserveIn > 0 && reserveOut > 0, 'ImpossibleLibrary: INSUFFICIENT_LIQUIDITY');
        }
        uint256 artiLiqTerm;
        bool isXybk;
        {
            // Avoid stack too deep
            uint256 fee;
            (fee, isXybk) = IImpossiblePair(pair).getFeeAndXybk();
            amountInPostFee = amountIn.mul(10000 - fee);
        }

        /// If xybk invariant, set reserveIn/reserveOut to artificial liquidity instead of actual liquidity
        if (isXybk) {
            (uint256 boost0, uint256 boost1) = IImpossiblePair(pair).calcBoost();
            uint256 sqrtK = xybkComputeSqrtK(isMatch, reserveIn, reserveOut, boost0, boost1);
            /// since balance0=balance1 only at sqrtK, if final balanceIn >= sqrtK means balanceIn >= balanceOut
            /// Use post-fee balances to maintain consistency with pair contract K invariant check
            if (amountInPostFee.add(reserveIn.mul(10000)) >= sqrtK.mul(10000)) {
                /// If tokenIn = token0, balanceIn > sqrtK => balance0>sqrtK, use boost0
                artiLiqTerm = calcArtiLiquidityTerm(isMatch ? boost0 : boost1, sqrtK);
                /// If balance started from <sqrtK and ended at >sqrtK and boosts are different, there'll be different amountIn/Out
                /// Don't need to check in other case for reserveIn < reserveIn.add(x) <= sqrtK since that case doesnt cross midpt
                if (reserveIn < sqrtK && boost0 != boost1) {
                    /// Break into 2 trades => start point -> midpoint (sqrtK, sqrtK), then midpoint -> final point
                    amountOut = reserveOut.sub(sqrtK);
                    amountInPostFee = amountInPostFee.sub((sqrtK.sub(reserveIn)).mul(10000));
                    reserveIn = sqrtK;
                    reserveOut = sqrtK;
                }
            } else {
                /// If tokenIn = token0, balanceIn < sqrtK => balance0<sqrtK, use boost1
                artiLiqTerm = calcArtiLiquidityTerm(isMatch ? boost1 : boost0, sqrtK);
            }
        }
        uint256 numerator = amountInPostFee.mul(reserveOut.add(artiLiqTerm));
        uint256 denominator = (reserveIn.add(artiLiqTerm)).mul(10000).add(amountInPostFee);
        uint256 lastSwapAmountOut = numerator / denominator;
        amountOut = (lastSwapAmountOut > reserveOut) ? reserveOut.add(amountOut) : lastSwapAmountOut.add(amountOut);
    }

    /**
     @notice Quotes minimum input given exact output amount of tokens and addresses of tokens in pair
     @dev The library function considers custom swap fees/invariants/asymmetric tuning of pairs
     @dev However, library function doesn't consider limits created by hardstops
     @param amountOut The desired output amount of token A
     @param tokenIn The address of input token
     @param tokenOut The address of output token
     @param factory The address of the factory contract
     @return amountIn The minimum input amount of token A for a valid swap
    */
    function getAmountIn(
        uint256 amountOut,
        address tokenIn,
        address tokenOut,
        address factory
    ) internal view returns (uint256 amountIn) {
        require(amountOut > 0, 'ImpossibleLibrary: INSUFFICIENT_INPUT_AMOUNT');

        uint256 reserveIn;
        uint256 reserveOut;
        uint256 artiLiqTerm;
        uint256 fee;
        bool isMatch;
        {
            // Avoid stack too deep
            bool isXybk;
            uint256 boost0;
            uint256 boost1;
            {
                // Avoid stack too deep
                (address token0, ) = sortTokens(tokenIn, tokenOut);
                isMatch = tokenIn == token0;
            }
            {
                // Avoid stack too deep
                address pair;
                (reserveIn, reserveOut, pair) = getReserves(factory, tokenIn, tokenOut);
                require(reserveIn > 0 && reserveOut > 0, 'ImpossibleLibrary: INSUFFICIENT_LIQUIDITY');
                (fee, isXybk) = IImpossiblePair(pair).getFeeAndXybk();
                (boost0, boost1) = IImpossiblePair(pair).calcBoost();
            }
            if (isXybk) {
                uint256 sqrtK = xybkComputeSqrtK(isMatch, reserveIn, reserveOut, boost0, boost1);
                /// since balance0=balance1 only at sqrtK, if final balanceOut >= sqrtK means balanceOut >= balanceIn
                if (reserveOut.sub(amountOut) >= sqrtK) {
                    /// If tokenIn = token0, balanceOut > sqrtK => balance1>sqrtK, use boost1
                    artiLiqTerm = calcArtiLiquidityTerm(isMatch ? boost1 : boost0, sqrtK);
                } else {
                    /// If tokenIn = token0, balanceOut < sqrtK => balance0>sqrtK, use boost0
                    artiLiqTerm = calcArtiLiquidityTerm(isMatch ? boost0 : boost1, sqrtK);
                    /// If balance started from <sqrtK and ended at >sqrtK and boosts are different, there'll be different amountIn/Out
                    /// Don't need to check in other case for reserveOut > reserveOut.sub(x) >= sqrtK since that case doesnt cross midpt
                    if (reserveOut > sqrtK && boost0 != boost1) {
                        /// Break into 2 trades => start point -> midpoint (sqrtK, sqrtK), then midpoint -> final point
                        amountIn = sqrtK.sub(reserveIn).mul(10000); /// Still need to divide by (10000 - fee). Do with below calculation to prevent early truncation
                        amountOut = amountOut.sub(reserveOut.sub(sqrtK));
                        reserveOut = sqrtK;
                        reserveIn = sqrtK;
                    }
                }
            }
        }
        uint256 numerator = (reserveIn.add(artiLiqTerm)).mul(amountOut).mul(10000);
        uint256 denominator = (reserveOut.add(artiLiqTerm)).sub(amountOut);
        amountIn = (amountIn.add((numerator / denominator)).div(10000 - fee)).add(1);
    }

    /**
     @notice Quotes maximum output given some uncertain input amount of tokens and addresses of tokens in pair
     @dev The library function considers custom swap fees/invariants/asymmetric tuning of pairs
     @dev However, library function doesn't consider limits created by hardstops
     @param tokenIn The address of input token
     @param tokenOut The address of output token
     @param factory The address of the factory contract
     @return uint256 The maximum possible output amount of token A
     @return uint256 The maximum possible output amount of token B
    */
    function getAmountOutFeeOnTransfer(
        address tokenIn,
        address tokenOut,
        address factory
    ) internal view returns (uint256, uint256) {
        uint256 reserveIn;
        uint256 reserveOut;
        address pair;
        bool isMatch;
        {
            // Avoid stack too deep
            (address token0, ) = sortTokens(tokenIn, tokenOut);
            isMatch = tokenIn == token0;
            (reserveIn, reserveOut, pair) = getReserves(factory, tokenIn, tokenOut); /// Should be reserve0/1 but reuse variables to save stack
            require(reserveIn > 0 && reserveOut > 0, 'ImpossibleLibrary: INSUFFICIENT_LIQUIDITY');
        }
        uint256 amountOut;
        uint256 artiLiqTerm;
        uint256 amountInPostFee;
        bool isXybk;
        {
            // Avoid stack too deep
            uint256 fee;
            uint256 balanceIn = IERC20(tokenIn).balanceOf(address(pair));
            require(balanceIn > reserveIn, 'ImpossibleLibrary: INSUFFICIENT_INPUT_AMOUNT');
            (fee, isXybk) = IImpossiblePair(pair).getFeeAndXybk();
            amountInPostFee = (balanceIn.sub(reserveIn)).mul(10000 - fee);
        }
        /// If xybk invariant, set reserveIn/reserveOut to artificial liquidity instead of actual liquidity
        if (isXybk) {
            (uint256 boost0, uint256 boost1) = IImpossiblePair(pair).calcBoost();
            uint256 sqrtK = xybkComputeSqrtK(isMatch, reserveIn, reserveOut, boost0, boost1);
            /// since balance0=balance1 only at sqrtK, if final balanceIn >= sqrtK means balanceIn >= balanceOut
            /// Use post-fee balances to maintain consistency with pair contract K invariant check
            if (amountInPostFee.add(reserveIn.mul(10000)) >= sqrtK.mul(10000)) {
                /// If tokenIn = token0, balanceIn > sqrtK => balance0>sqrtK, use boost0
                artiLiqTerm = calcArtiLiquidityTerm(isMatch ? boost0 : boost1, sqrtK);
                /// If balance started from <sqrtK and ended at >sqrtK and boosts are different, there'll be different amountIn/Out
                /// Don't need to check in other case for reserveIn < reserveIn.add(x) <= sqrtK since that case doesnt cross midpt
                if (reserveIn < sqrtK && boost0 != boost1) {
                    /// Break into 2 trades => start point -> midpoint (sqrtK, sqrtK), then midpoint -> final point
                    amountOut = reserveOut.sub(sqrtK);
                    amountInPostFee = amountInPostFee.sub(sqrtK.sub(reserveIn));
                    reserveOut = sqrtK;
                    reserveIn = sqrtK;
                }
            } else {
                /// If tokenIn = token0, balanceIn < sqrtK => balance0<sqrtK, use boost0
                artiLiqTerm = calcArtiLiquidityTerm(isMatch ? boost1 : boost0, sqrtK);
            }
        }
        uint256 numerator = amountInPostFee.mul(reserveOut.add(artiLiqTerm));
        uint256 denominator = (reserveIn.add(artiLiqTerm)).mul(10000).add(amountInPostFee);
        uint256 lastSwapAmountOut = numerator / denominator;
        amountOut = (lastSwapAmountOut > reserveOut) ? reserveOut.add(amountOut) : lastSwapAmountOut.add(amountOut);
        return isMatch ? (uint256(0), amountOut) : (amountOut, uint256(0));
    }

    /**
     @notice Quotes maximum output given exact input amount of tokens and addresses of tokens in trade sequence
     @dev The library function considers custom swap fees/invariants/asymmetric tuning of pairs
     @dev However, library function doesn't consider limits created by hardstops
     @param factory The address of the IF factory
     @param amountIn The input amount of token A
     @param path[] An array of token addresses. Trades are made from arr idx 0 to arr end idx sequentially
     @return amounts The maximum possible output amount of all tokens through sequential swaps
    */
    function getAmountsOut(
        address factory,
        uint256 amountIn,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, 'ImpossibleLibrary: INVALID_PATH');
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            amounts[i + 1] = getAmountOut(amounts[i], path[i], path[i + 1], factory);
        }
    }

    /**
     @notice Quotes minimum input given exact output amount of tokens and addresses of tokens in trade sequence
     @dev The library function considers custom swap fees/invariants/asymmetric tuning of pairs
     @dev However, library function doesn't consider limits created by hardstops
     @param factory The address of the IF factory
     @param amountOut The output amount of token A
     @param path[] An array of token addresses. Trades are made from arr idx 0 to arr end idx sequentially
     @return amounts The minimum output amount required of all tokens through sequential swaps
    */
    function getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, 'ImpossibleLibrary: INVALID_PATH');
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            amounts[i - 1] = getAmountIn(amounts[i], path[i - 1], path[i], factory);
        }
    }

    /**
     @notice Computes sqrt of invariant K in xybk formula given state of boost, balances
     @dev More details on math at: https://docs.impossible.finance/impossible-swap/swap-math
     @param isMatch Boolean if tokenA == token0
     @param reserveIn Amount of reserveIn tokens
     @param reserveOut Amount of reserveOut tokens
     @param boost0 The boost0 value in the pair
     @param boost1 The boost1 value in the pair
     @return uint256 The sqrt of the invariant K in this case
    */
    function xybkComputeSqrtK(
        bool isMatch,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 boost0,
        uint256 boost1
    ) internal pure returns (uint256) {
        uint256 boost =
            isMatch
                ? ((reserveIn > reserveOut) ? boost0.sub(1) : boost1.sub(1))
                : ((reserveOut > reserveIn) ? boost0.sub(1) : boost1.sub(1));
        uint256 denom = boost.mul(2).add(1); // 1+2*boost
        uint256 term = boost.mul(reserveIn.add(reserveOut)).div(denom.mul(2)); // boost*(x+y)/(2+4*boost)
        return Math.sqrt(term**2 + reserveIn.mul(reserveOut).div(denom)) + term;
    }
}
