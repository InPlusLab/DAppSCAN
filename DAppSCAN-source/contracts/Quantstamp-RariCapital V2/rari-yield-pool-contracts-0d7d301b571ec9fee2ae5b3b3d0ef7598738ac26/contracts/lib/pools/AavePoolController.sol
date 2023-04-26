/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public (i.e., non-administrative) application programming interfaces (APIs) of the official Ethereum smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license), provided that the application does not abuse the APIs or act against the interests of Rari Capital, Inc.
 * Anyone is free to study, review, and analyze the source code contained in this package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in this package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity 0.5.17;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "../../external/aave/LendingPool.sol";
import "../../external/aave/AToken.sol";

/**
 * @title AavePoolController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This library handles deposits to and withdrawals from Aave liquidity pools.
 */
library AavePoolController {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /**
     * @dev Aave LendingPool contract address.
     */
    address constant private LENDING_POOL_CONTRACT = 0x398eC7346DcD622eDc5ae82352F02bE94C62d119;

    /**
     * @dev Aave LendingPool contract object.
     */
    LendingPool constant private _lendingPool = LendingPool(LENDING_POOL_CONTRACT);

    /**
     * @dev Aave LendingPoolCore contract address.
     */
    address constant private LENDING_POOL_CORE_CONTRACT = 0x3dfd23A6c5E8BbcFc9581d2E864a68feb6a076d3;

    /**
     * @dev Returns a token's aToken contract address given its ERC20 contract address.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function getATokenContract(address erc20Contract) private pure returns (address) {
        if (erc20Contract == 0x6B175474E89094C44Da98b954EedeAC495271d0F) return 0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d; // DAI => aDAI
        if (erc20Contract == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) return 0x9bA00D6856a4eDF4665BcA2C2309936572473B7E; // USDC => aUSDC
        if (erc20Contract == 0xdAC17F958D2ee523a2206206994597C13D831ec7) return 0x71fc860F7D3A592A4a98740e39dB31d25db65ae8; // USDT => aUSDT
        if (erc20Contract == 0x0000000000085d4780B73119b644AE5ecd22b376) return 0x4DA9b813057D04BAef4e5800E36083717b4a0341; // TUSD => aTUSD
        if (erc20Contract == 0x4Fabb145d64652a948d72533023f6E7A623C7C53) return 0x6Ee0f7BB50a54AB5253dA0667B0Dc2ee526C30a8; // BUSD => aBUSD
        if (erc20Contract == 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51) return 0x625aE63000f46200499120B906716420bd059240; // sUSD => aSUSD
        else revert("Supported Aave aToken address not found for this token address.");
    }

    /**
     * @dev Returns the fund's balance of the specified currency in the Aave pool.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function getBalance(address erc20Contract) external view returns (uint256) {
        AToken aToken = AToken(getATokenContract(erc20Contract));
        return aToken.balanceOf(address(this));
    }

    /**
     * @dev Approves tokens to Aave without spending gas on every deposit.
     * @param erc20Contract The ERC20 contract address of the token.
     * @param amount Amount of the specified token to approve to Aave.
     */
    function approve(address erc20Contract, uint256 amount) external {
        IERC20 token = IERC20(erc20Contract);
        uint256 allowance = token.allowance(address(this), LENDING_POOL_CORE_CONTRACT);
        if (allowance == amount) return;
        if (amount > 0 && allowance > 0) token.safeApprove(LENDING_POOL_CORE_CONTRACT, 0);
        token.safeApprove(LENDING_POOL_CORE_CONTRACT, amount);
        return;
    }

    /**
     * @dev Deposits funds to the Aave pool. Assumes that you have already approved >= the amount to Aave.
     * @param erc20Contract The ERC20 contract address of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     * @param referralCode Referral code.
     */
    function deposit(address erc20Contract, uint256 amount, uint16 referralCode) external {
        require(amount > 0, "Amount must be greater than 0.");
        _lendingPool.deposit(erc20Contract, amount, referralCode);
    }

    /**
     * @dev Withdraws funds from the Aave pool.
     * @param erc20Contract The ERC20 contract address of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     */
    function withdraw(address erc20Contract, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        AToken aToken = AToken(getATokenContract(erc20Contract));
        aToken.redeem(amount);
    }

    /**
     * @dev Withdraws all funds from the Aave pool.
     * @param erc20Contract The ERC20 contract address of the token to be withdrawn.
     * @return Boolean indicating success.
     */
    function withdrawAll(address erc20Contract) external returns (bool) {
        AToken aToken = AToken(getATokenContract(erc20Contract));
        uint256 balance = aToken.balanceOf(address(this));
        if (balance <= 0) return false;
        aToken.redeem(balance);
        return true;
    }
}
