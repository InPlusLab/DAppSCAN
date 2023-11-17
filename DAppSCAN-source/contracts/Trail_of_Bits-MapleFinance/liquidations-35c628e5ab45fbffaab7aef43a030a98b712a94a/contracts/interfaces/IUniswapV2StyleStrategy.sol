// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

interface IUniswapV2StyleStrategy {

    /**
     * @dev View function that returns the router that is used by the strategy
     */
    function ROUTER() external view returns (address router_);

    /**
     * @dev Function that performs a `swapExactTokensForTokens` swap on a UniswapV2-style AMM, sending the remaining funds
     * @dev from the flashloan to the specified `profitDestination`.
     * @param swapAmount_         Amount of `collateralAsset_` to be swapped.
     * @param minReturnAmount_    Minimum amount of `fundsAsset_` to be returned from the swap.
     * @param collateralAsset_    Asset that is swapped from.
     * @param middleAsset_        Optional middle asset to add to `path` of the AMM.
     * @param fundsAsset_         Asset to be swapped to.
     * @param profitDestination_  Address that remaining fudns are sent to.
     */
    function swap(
        uint256 swapAmount_,
        uint256 minReturnAmount_,
        address collateralAsset_,
        address middleAsset_,
        address fundsAsset_,
        address profitDestination_
    ) external;

    /**
     * @dev Function that calls `liquidatePortion` in the liquidator, flash-borrowing funds to swap.
     * @param lender_             Address that will flashloan `swapAmount_` of `collateralAsset`
     * @param swapAmount_         Amount of `collateralAsset_` to be swapped.
     * @param collateralAsset_    Asset that is flash-borrowed.
     * @param middleAsset_        Optional middle asset to add to `path` of the AMM.
     * @param fundsAsset_         Asset to be swapped to.
     * @param profitDestination_  Address that remaining fudns are sent to.
     */
    function flashBorrowLiquidation(
        address lender_, 
        uint256 swapAmount_,
        address collateralAsset_,
        address middleAsset_,
        address fundsAsset_,
        address profitDestination_
    ) external;
}

