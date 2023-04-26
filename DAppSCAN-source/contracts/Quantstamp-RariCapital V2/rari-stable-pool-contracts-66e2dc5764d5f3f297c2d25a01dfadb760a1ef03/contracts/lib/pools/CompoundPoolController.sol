/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public APIs (described in `API.md` of the `rari-contracts` package) of the official smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license) benefitting Rari Capital, Inc.
 * Only those with explicit permission from a co-founder of Rari Capital (Jai Bhavnani, Jack Lipstone, or David Lucid) are permitted to study, review, or analyze any part of the source code contained in the `rari-contracts` package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in the `rari-contracts` package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity ^0.5.7;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../external/compound/CErc20.sol";

/**
 * @title CompoundPoolController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This library handles deposits to and withdrawals from dYdX liquidity pools.
 */
library CompoundPoolController {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /**
     * @notice Package version of `rari-contracts` when this contract was deployed.
     */
    string public constant VERSION = "2.0.0";

    /**
     * @dev Returns a token's cToken contract address given its ERC20 contract address.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function getCErc20Contract(address erc20Contract) private pure returns (address) {
        if (erc20Contract == 0x6B175474E89094C44Da98b954EedeAC495271d0F) return 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643; // DAI => cDAI
        if (erc20Contract == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) return 0x39AA39c021dfbaE8faC545936693aC917d5E7563; // USDC => cUSDC
        if (erc20Contract == 0xdAC17F958D2ee523a2206206994597C13D831ec7) return 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9; // USDT => cUSDT
        else revert("Supported Compound cToken address not found for this token address.");
    }

    /**
     * @dev Returns the fund's balance of the specified currency in the Compound pool.
     * We would simply be using balanceOfUnderlying, but exchangeRateCurrent is nonReentrant, which causes us issues.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function getBalance(address erc20Contract) external returns (uint256) {
        CErc20 cErc20 = CErc20(getCErc20Contract(erc20Contract));
        cErc20.accrueInterest();
        return cErc20.balanceOf(address(this)).mul(cErc20.exchangeRateStored()).div(1e18);
    }

    /**
     * @dev Approves tokens to Compound without spending gas on every deposit.
     * @param erc20Contract The ERC20 contract address of the token.
     * @param amount Amount of the specified token to approve to Compound.
     */
    function approve(address erc20Contract, uint256 amount) external {
        address cErc20Contract = getCErc20Contract(erc20Contract);
        IERC20 token = IERC20(erc20Contract);
        uint256 allowance = token.allowance(address(this), cErc20Contract);
        if (allowance == amount) return;
        if (amount > 0 && allowance > 0) token.safeApprove(cErc20Contract, 0);
        token.safeApprove(cErc20Contract, amount);
        return;
    }

    /**
     * @dev Deposits funds to the Compound pool. Assumes that you have already approved >= the amount to Compound.
     * @param erc20Contract The ERC20 contract address of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     */
    function deposit(address erc20Contract, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        CErc20 cErc20 = CErc20(getCErc20Contract(erc20Contract));
        uint256 mintResult = cErc20.mint(amount);
        require(mintResult == 0, "Error calling mint on Compound cToken: error code not equal to 0.");
    }

    /**
     * @dev Withdraws funds from the Compound pool.
     * @param erc20Contract The ERC20 contract address of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     */
    function withdraw(address erc20Contract, uint256 amount) external {
        require(amount > 0, "Amount must be greater than to 0.");
        CErc20 cErc20 = CErc20(getCErc20Contract(erc20Contract));
        uint256 redeemResult = cErc20.redeemUnderlying(amount);
        require(redeemResult == 0, "Error calling redeemUnderlying on Compound cToken: error code not equal to 0.");
    }

    /**
     * @dev Withdraws all funds from the Compound pool.
     * @param erc20Contract The ERC20 contract address of the token to be withdrawn.
     * @return Boolean indicating success.
     */
    function withdrawAll(address erc20Contract) external returns (bool) {
        CErc20 cErc20 = CErc20(getCErc20Contract(erc20Contract));
        uint256 balance = cErc20.balanceOf(address(this));
        if (balance <= 0) return false; // TODO: Or revert("No funds available to redeem from Compound cToken.")
        uint256 redeemResult = cErc20.redeem(balance);
        require(redeemResult == 0, "Error calling redeem on Compound cToken: error code not equal to 0.");
        return true;
    }
}
