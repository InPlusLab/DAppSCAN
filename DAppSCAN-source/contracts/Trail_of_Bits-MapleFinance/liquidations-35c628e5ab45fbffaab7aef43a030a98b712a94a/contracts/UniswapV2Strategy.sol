// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";

import { IERC20Like, ILiquidatorLike, IUniswapRouterLike } from "./interfaces/Interfaces.sol";
import { IUniswapV2StyleStrategy }                         from "./interfaces/IUniswapV2StyleStrategy.sol";

contract UniswapV2Strategy is IUniswapV2StyleStrategy {

    address public constant override ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    function flashBorrowLiquidation(
        address lender_, 
        uint256 swapAmount_,
        address collateralAsset_,
        address middleAsset_,
        address fundsAsset_,
        address profitDestination_
    ) 
        external override 
    {
        uint256 repaymentAmount = ILiquidatorLike(lender_).getExpectedAmount(swapAmount_);

        ERC20Helper.approve(fundsAsset_, lender_, repaymentAmount);

        ILiquidatorLike(lender_).liquidatePortion(
            swapAmount_,  
            abi.encodeWithSelector(
                this.swap.selector, 
                swapAmount_, 
                repaymentAmount, 
                collateralAsset_, 
                middleAsset_, 
                fundsAsset_,
                profitDestination_
            )
        );
    }

    function swap(
        uint256 swapAmount_,
        uint256 minReturnAmount_,
        address collateralAsset_,
        address middleAsset_,
        address fundsAsset_,
        address profitDestination_
    )
        external override
    {
        require(IERC20Like(collateralAsset_).balanceOf(address(this)) == swapAmount_, "UniswapV2Strategy:WRONG_COLLATERAL_AMT");
        
        ERC20Helper.approve(collateralAsset_, ROUTER, swapAmount_);

        bool hasMiddleAsset = middleAsset_ != fundsAsset_ && middleAsset_ != address(0);

        address[] memory path = new address[](hasMiddleAsset ? 3 : 2);

        path[0] = address(collateralAsset_);
        path[1] = hasMiddleAsset ? middleAsset_ : fundsAsset_;

        if (hasMiddleAsset) path[2] = fundsAsset_;

        IUniswapRouterLike(ROUTER).swapExactTokensForTokens(
            swapAmount_,
            minReturnAmount_,
            path,
            address(this),
            block.timestamp
        );

        require(ERC20Helper.transfer(fundsAsset_, profitDestination_, IERC20Like(fundsAsset_).balanceOf(address(this)) - minReturnAmount_), "UniswapV2Strategy:PROFIT_TRANSFER");
    }

}

