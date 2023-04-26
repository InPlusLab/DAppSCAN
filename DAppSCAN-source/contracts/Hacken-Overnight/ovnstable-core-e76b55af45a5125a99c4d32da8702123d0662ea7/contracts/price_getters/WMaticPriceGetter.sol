// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../price_getters/AbstractPriceGetter.sol";
import "../connectors/swaps/interfaces/IUniswapV2Router02.sol";

contract WMaticPriceGetter is AbstractPriceGetter {
    IUniswapV2Router02 public swapRouter;
    IERC20 public usdcToken;
    IERC20 public wMaticToken;

    constructor(
        address _swapRouter,
        address _usdcToken,
        address _wMaticToken
    ) {
        require(_swapRouter != address(0), "Zero address not allowed");
        require(_usdcToken != address(0), "Zero address not allowed");
        require(_wMaticToken != address(0), "Zero address not allowed");

        swapRouter = IUniswapV2Router02(_swapRouter);
        usdcToken = IERC20(_usdcToken);
        wMaticToken = IERC20(_wMaticToken);
    }

    function getUsdcBuyPrice() external view override returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(usdcToken);
        path[1] = address(wMaticToken);

        uint[] memory amountsOut = swapRouter.getAmountsOut(10**6, path);
        // 6 + 12 + 18 - 18 = 18
        return (amountsOut[0] * (10**12) * DENOMINATOR) / amountsOut[1];
    }

    function getUsdcSellPrice() external view override returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(wMaticToken);
        path[1] = address(usdcToken);

        uint[] memory amountsOut = swapRouter.getAmountsOut(10**18, path);
        // 6 + 12 + 18 - 18 = 18
        return (amountsOut[1] * (10**12) * DENOMINATOR) / amountsOut[0];
    }
}
