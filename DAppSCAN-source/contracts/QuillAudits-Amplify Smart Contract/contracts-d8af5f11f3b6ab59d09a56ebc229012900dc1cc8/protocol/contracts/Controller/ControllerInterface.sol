// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../InterestRate/InterestRateModel.sol";
import "../Asset/AssetInterface.sol";
import "../LossProvisionPool/LossProvisionInterface.sol";
import { IERC20 } from "../ERC20/IERC20.sol";

abstract contract ControllerInterface {
    // Policy hooks
    function lendAllowed(address pool, address lender, uint256 amount) external virtual returns (uint256);
    function redeemAllowed(address pool, address redeemer, uint256 tokens) external virtual returns (uint256);
    function borrowAllowed(address pool, address borrower, uint256 amount) external virtual returns (uint256);
    function repayAllowed(address pool, address payer, address borrower, uint256 amount) external virtual returns (uint256);
    function createCreditLineAllowed(address pool, address borrower, uint256 collateralAsset) external virtual returns (uint256, uint256, uint256, uint256, uint256);


    function provisionPool() external virtual view returns (LossProvisionInterface);
    function interestRateModel() external virtual view returns (InterestRateModel);
    function assetsFactory() external virtual view returns (AssetInterface);
    function amptToken() external virtual view returns (IERC20);
    
    function containsStableCoin(address _stableCoin) external virtual view returns (bool);
    function getStableCoins() external virtual view returns (address[] memory);
}