/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public APIs (described in `API.md` of the `rari-contracts` package) of the official smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license) benefitting Rari Capital, Inc.
 * Only those with explicit permission from a co-founder of Rari Capital (Jai Bhavnani, Jack Lipstone, or David Lucid) are permitted to study, review, or analyze any part of the source code contained in the `rari-contracts` package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in the `rari-contracts` package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity 0.5.17;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "../../external/yvault/IVault.sol";

/**
 * @title YVaultPoolController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This library handles deposits to and withdrawals from yearn.finance's yVaults.
 */
library YVaultPoolController {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IVault;

    /**
     * @dev Returns a token's yVault contract address given its ERC20 contract address.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function getYVaultContract(address erc20Contract) private pure returns (address) {
        if (erc20Contract == 0x6B175474E89094C44Da98b954EedeAC495271d0F) return 0xACd43E627e64355f1861cEC6d3a6688B31a6F952; // DAI => DAI yVault
        if (erc20Contract == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) return 0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e; // USDC => USDC yVault
        if (erc20Contract == 0xdAC17F958D2ee523a2206206994597C13D831ec7) return 0x2f08119C6f07c006695E079AAFc638b8789FAf18; // USDT => USDT yVault
        if (erc20Contract == 0x0000000000085d4780B73119b644AE5ecd22b376) return 0x37d19d1c4E1fa9DC47bD1eA12f742a0887eDa74a; // TUSD => TUSD yVault
        else revert("Supported yearn.finance yVault address not found for this token address.");
    }

    /**
     * @dev Returns the fund's balance of the specified currency in the yVault.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function getBalance(address erc20Contract) external view returns (uint256) {
        IVault yVault = IVault(getYVaultContract(erc20Contract));
        return yVault.balanceOf(address(this)).mul(yVault.getPricePerFullShare()).div(1e18);
    }

    /**
     * @dev Approves tokens to a yVault without spending gas on every deposit.
     * @param erc20Contract The ERC20 contract address of the token.
     * @param amount Amount of the specified token to approve.
     */
    function approve(address erc20Contract, uint256 amount) external {
        address yVaultContract = getYVaultContract(erc20Contract);
        IERC20 token = IERC20(erc20Contract);
        uint256 allowance = token.allowance(address(this), yVaultContract);
        if (allowance == amount) return;
        if (amount > 0 && allowance > 0) token.safeApprove(yVaultContract, 0);
        token.safeApprove(yVaultContract, amount);
        return;
    }

    /**
     * @dev Deposits funds to the yVault. Assumes that you have already approved >= the amount to the yVault.
     * @param erc20Contract The ERC20 contract address of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     */
    function deposit(address erc20Contract, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        IVault yVault = IVault(getYVaultContract(erc20Contract));
        yVault.deposit(amount);
    }

    /**
     * @dev Withdraws funds from the yVault.
     * @param erc20Contract The ERC20 contract address of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     */
    function withdraw(address erc20Contract, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        IVault yVault = IVault(getYVaultContract(erc20Contract));
        uint256 pricePerFullShare = yVault.getPricePerFullShare();
        uint256 shares = amount.mul(1e18).div(pricePerFullShare);
        if (shares.mul(pricePerFullShare).div(1e18) < amount) shares++; // Round up if necessary (i.e., if the division above left a remainder)
        yVault.withdraw(shares);
    }

    /**
     * @dev Withdraws all funds from the yVault.
     * @param erc20Contract The ERC20 contract address of the token to be withdrawn.
     * @return Boolean indicating if any funds were withdrawn.
     */
    function withdrawAll(address erc20Contract) external returns (bool) {
        IVault yVault = IVault(getYVaultContract(erc20Contract));
        uint256 balance = yVault.balanceOf(address(this));
        if (balance <= 0) return false;
        yVault.withdraw(balance);
        return true;
    }

    /**
     * @dev Transfers all funds in the yVault to another address.
     * @param erc20Contract The ERC20 contract address of the underlying token.
     * @param to The recipient of the funds.
     * @return Boolean indicating if any funds were transferred.
     */
    function transferAll(address erc20Contract, address to) external returns (bool) {
        IVault yVault = IVault(getYVaultContract(erc20Contract));
        uint256 balance = yVault.balanceOf(address(this));
        if (balance <= 0) return false;
        yVault.safeTransfer(to, balance);
        return true;
    }
}
