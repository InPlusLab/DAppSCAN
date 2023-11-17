// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IERC20Like, IMapleGlobalsLike, IOracleLike, IUniswapRouterLike } from "../../interfaces/Interfaces.sol";

import { StateManipulations } from "../../../modules/contract-test-utils/contracts/test.sol";

contract AuctioneerMock {

    address public owner;
    address public collateralAsset;
    address public fundsAsset;
    address public globals;
    uint256 public allowedSlippage;
    uint256 public minRatio;

    constructor(address globals_, address collateralAsset_, address fundsAsset_, uint256 allowedSlippage_, uint256 minRatio_) {
        owner           = msg.sender;
        globals         = globals_;
        collateralAsset = collateralAsset_;
        fundsAsset      = fundsAsset_;
        allowedSlippage = allowedSlippage_;
        minRatio        = minRatio_;
    }

    function getExpectedAmount(uint256 swapAmount_) public view returns (uint256 returnAmount_) {
        uint256 oracleAmount = 
            swapAmount_
                * IMapleGlobalsLike(globals).getLatestPrice(collateralAsset)  // Convert from `fromAsset` value.
                * 10 ** IERC20Like(fundsAsset).decimals()                     // Convert to `toAsset` decimal precision.
                * (10_000 - allowedSlippage)                                  // Multiply by allowed slippage basis points
                / IMapleGlobalsLike(globals).getLatestPrice(fundsAsset)       // Convert to `toAsset` value.
                / 10 ** IERC20Like(collateralAsset).decimals()                // Convert from `fromAsset` decimal precision.
                / 10_000;                                                     // Divide basis points for slippage
        
        uint256 minRatioAmount = swapAmount_ * minRatio / 10 ** IERC20Like(collateralAsset).decimals();

        return oracleAmount > minRatioAmount ? oracleAmount : minRatioAmount;
    }
}

contract MapleGlobalsMock {

    mapping (address => address) public oracleFor;

    function getLatestPrice(address asset) external view returns (uint256) {
        (, int256 price,,,) = IOracleLike(oracleFor[asset]).latestRoundData();
        return uint256(price);
    }

    function setPriceOracle(address asset, address oracle) external {
        oracleFor[asset] = oracle;
    }

}

// Contract to perform fake arbitrage transactions to prop price back up
contract Rebalancer is StateManipulations {

    function swap(
        address router_,
        uint256 amountOut_,
        uint256 amountInMax_,
        address fromAsset_,
        address middleAsset_,
        address toAsset_
    )
        external
    {
        IERC20Like(fromAsset_).approve(router_, amountInMax_);

        bool hasMiddleAsset = middleAsset_ != toAsset_ && middleAsset_ != address(0);

        address[] memory path = new address[](hasMiddleAsset ? 3 : 2);

        path[0] = address(fromAsset_);
        path[1] = hasMiddleAsset ? middleAsset_ : toAsset_;

        if (hasMiddleAsset) path[2] = toAsset_;

        IUniswapRouterLike(router_).swapTokensForExactTokens(
            amountOut_,
            amountInMax_,
            path,
            address(this),
            block.timestamp
        );
    }

}
