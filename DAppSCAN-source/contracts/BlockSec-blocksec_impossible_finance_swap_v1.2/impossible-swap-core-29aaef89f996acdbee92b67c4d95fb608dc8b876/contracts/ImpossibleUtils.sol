// SPDX-License-Identifier: GPL-3
pragma solidity =0.7.6;

import './libraries/ImpossibleLibrary.sol';

contract ImpossibleUtils {
    using SafeMath for uint256;

    address public immutable factory;

    /**
     @notice Constructor for IF Utility Contract
     @param _pairFactory Address of IF Pair Factory
    */
    constructor(address _pairFactory) {
        factory = _pairFactory;
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
    ) external pure virtual returns (uint256 amountB) {
        return ImpossibleLibrary.quote(amountA, reserveA, reserveB);
    }

    /**
     @notice Quotes maximum output given exact input amount of tokens and addresses of tokens in pair
     @dev The library function considers custom swap fees/invariants/asymmetric tuning of pairs
     @dev However, library function doesn't consider limits created by hardstops
     @param amountIn The input amount of token A
     @param tokenIn The address of input token
     @param tokenOut The address of output token
     @return uint256 The maximum output amount of token B for a valid swap
    */
    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256) {
        return ImpossibleLibrary.getAmountOut(amountIn, tokenIn, tokenOut, factory);
    }

    /**
     @notice Quotes minimum input given exact output amount of tokens and addresses of tokens in pair
     @dev The library function considers custom swap fees/invariants/asymmetric tuning of pairs
     @dev However, library function doesn't consider limits created by hardstops
     @param amountOut The desired output amount of token A
     @param tokenIn The address of input token
     @param tokenOut The address of output token
     @return uint256 The minimum input amount of token A for a valid swap
    */
    function getAmountIn(
        uint256 amountOut,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256) {
        return ImpossibleLibrary.getAmountIn(amountOut, tokenIn, tokenOut, factory);
    }

    /**
     @notice Quotes maximum output given exact input amount of tokens and addresses of tokens in trade sequence
     @dev The library function considers custom swap fees/invariants/asymmetric tuning of pairs
     @dev However, library function doesn't consider limits created by hardstops
     @param amountIn The input amount of token A
     @param path[] An array of token addresses. Trades are made from arr idx 0 to arr end idx sequentially
     @return amounts The maximum possible output amount of all tokens through sequential swaps
    */
    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        virtual
        returns (uint256[] memory amounts)
    {
        return ImpossibleLibrary.getAmountsOut(factory, amountIn, path);
    }

    /**
     @notice Quotes minimum input given exact output amount of tokens and addresses of tokens in trade sequence
     @dev The library function considers custom swap fees/invariants/asymmetric tuning of pairs
     @dev However, library function doesn't consider limits created by hardstops
     @param amountOut The output amount of token A
     @param path[] An array of token addresses. Trades are made from arr idx 0 to arr end idx sequentially
     @return amounts The minimum output amount required of all tokens through sequential swaps
    */
    function getAmountsIn(uint256 amountOut, address[] memory path)
        external
        view
        virtual
        returns (uint256[] memory amounts)
    {
        return ImpossibleLibrary.getAmountsIn(factory, amountOut, path);
    }
}
