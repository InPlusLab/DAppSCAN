//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./modules/amm/interfaces/IUniswapRouter02.sol";
import "./modules/kap20/interfaces/IKAP20.sol";
import "./interfaces/IMarketImpl.sol";

contract MarketImpl is IMarketImpl {
//    SWC-114-Transaction Order Dependence:L32-34、37、45-47
    function merketSell(
        address market,
        address srcToken,
        address destToken,
        uint256 amountIn,
        address payable beneficiary,
        uint256 slippageTolerrance
    ) external override returns (uint256) {
        uint256 INTERVAL = 5 * 60 * 60;
        uint256 deadline = block.timestamp + INTERVAL;
        uint256[] memory amounts;
        address[] memory path = new address[](2);
        uint256 amountOutMin;

        IUniswapRouter02 router = IUniswapRouter02(market);
        path[0] = srcToken;

        IKAP20(srcToken).approve(address(router), amountIn * 10);

        if (destToken == address(0)) {
            path[1] = router.WETH();
            amounts = router.getAmountsOut(amountIn, path);
            amountOutMin =
                (amounts[amounts.length - 1] * (1e18 - slippageTolerrance)) /
                1e18;
            amounts = router.swapExactTokensForETH(
                amountIn,
                amountOutMin,
                path,
                beneficiary,
                deadline
            );
        } else {
            path[1] = destToken;
            amounts = router.getAmountsOut(amountIn, path);
            amountOutMin =
                (amounts[amounts.length - 1] * (1e18 - slippageTolerrance)) /
                1e18;
            amounts = router.swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                beneficiary,
                deadline
            );
        }

        return amounts[amounts.length - 1];
    }
//    SWC-114-Transaction Order Dependence:L82、84、94、97
    function marketBuy(
        address market,
        address srcToken,
        address destToken,
        uint256 amountIn,
        address payable beneficiary,
        uint256 slippageTolerrance
    ) external payable override returns (uint256) {
        uint256 INTERVAL = 5 * 60 * 60;
        uint256 deadline = block.timestamp + INTERVAL;

        uint256[] memory amounts;
        address[] memory path = new address[](2);
        uint256 amountOutMin;

        IUniswapRouter02 router = IUniswapRouter02(market);

        if (srcToken == address(0)) {
            path[0] = router.WETH();
            path[1] = destToken;

            amounts = router.getAmountsOut(amountIn, path);
            amountOutMin = (amounts[amounts.length - 1] * (1e18 - slippageTolerrance)) / 1e18;
            amounts = router.swapExactETHForTokens{value: amountIn}(
                amountOutMin,
                path,
                beneficiary,
                deadline
            );
        } else {
            IKAP20(srcToken).approve(address(router), amountIn * 10);
            path[0] = srcToken;
            path[1] = destToken;
            amounts = router.getAmountsOut(amountIn, path);
            amountOutMin = (amounts[amounts.length - 1] * (1e18 - slippageTolerrance)) / 1e18;
            amounts = router.swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                beneficiary,
                deadline
            );
        }

        return amounts[amounts.length - 1];
    }
}
