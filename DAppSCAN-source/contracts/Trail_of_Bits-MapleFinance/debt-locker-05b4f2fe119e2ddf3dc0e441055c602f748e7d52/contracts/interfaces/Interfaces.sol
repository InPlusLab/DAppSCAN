// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

interface IERC20Like {

    function decimals() external view returns (uint256 decimals_);

    function balanceOf(address account_) external view returns (uint256 balanceOf_);

}

interface ILiquidatorLike {

    function auctioneer() external view returns (address auctioneer_);
}

interface IMapleGlobalsLike {

   function defaultUniswapPath(address fromAsset_, address toAsset_) external view returns (address intermediateAsset_);

   function investorFee() external view returns (uint256 investorFee_);

   function mapleTreasury() external view returns (address mapleTreasury_);

   function treasuryFee() external view returns (uint256 treasuryFee_);

   function getLatestPrice(address asset_) external view returns (uint256 price_);

}

interface IMapleLoanLike {

    function acceptNewTerms(address refinancer_, bytes[] calldata calls_, uint256 amount_) external;

    function claimableFunds() external view returns (uint256 claimableFunds_);

    function collateralAsset() external view returns (address collateralAsset_);

    function fundsAsset() external view returns (address fundsAsset_);

    function lender() external view returns (address lender_);

    function principal() external view returns (uint256 principal_);

    function principalRequested() external view returns (uint256 principalRequested_);

    function claimFunds(uint256 amount_, address destination_) external;

    function repossess(address destination_) external returns (uint256 collateralAssetAmount_, uint256 fundsAssetAmount_);

}

interface IPoolLike {

    function poolDelegate() external view returns (address poolDelegate_);

    function superFactory() external view returns (address superFactory_);

}

interface IPoolFactoryLike {

    function globals() external pure returns (address globals_);

}

interface IUniswapRouterLike {

    function swapExactTokensForTokens(
        uint amountIn_,
        uint amountOutMin_,
        address[] calldata path_,
        address to_,
        uint deadline_
    ) external returns (uint[] memory amounts_);

}
