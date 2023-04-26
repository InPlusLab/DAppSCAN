// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "../../external/mstable/ISavingsContract.sol";
import "../../external/mstable/IBoostedSavingsVault.sol";

/**
 * @title MStablePoolController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This library handles deposits to and withdrawals from mStable liquidity pools.
 */
library MStablePoolController {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /**
     * @dev mStable mUSD ERC20 token contract address.
     */
    address constant private MUSD_TOKEN_CONTRACT = 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5;

    /**
     * @dev mStable SavingsContract contract address.
     */
    address constant private SAVINGS_CONTRACT = 0x30647a72Dc82d7Fbb1123EA74716aB8A317Eac19;

    /**
     * @dev mStable SavingsContract contract object.
     */
    ISavingsContract constant private _savingsContract = ISavingsContract(SAVINGS_CONTRACT);

    /**
     * @dev mStable BoostedSavingsVault contract address.
     */
    address constant private SAVINGS_VAULT_CONTRACT = 0x78BefCa7de27d07DC6e71da295Cc2946681A6c7B;

    /**
     * @dev mStable BoostedSavingsVault contract object.
     */
    IBoostedSavingsVault constant private _savingsVault = IBoostedSavingsVault(SAVINGS_VAULT_CONTRACT);

    /**
     * @dev Returns the fund's mUSD token balance supplied to the mStable savings contract.
     */
    function getBalance() external view returns (uint256) {
        return _savingsVault.rawBalanceOf(address(this)).mul(_savingsContract.exchangeRate()).div(1e18);
    }

    /**
     * @dev Approves mUSD tokens to the mStable savings contract and imUSD to the savings vault without spending gas on every deposit.
     * @param amount Amount of mUSD tokens to approve to the mStable savings contract.
     */
    function approve(uint256 amount) external {
        // Approve mUSD to the savings contract (imUSD)
        IERC20 token = IERC20(MUSD_TOKEN_CONTRACT);
        uint256 allowance = token.allowance(address(this), SAVINGS_CONTRACT);
        if (allowance == amount) return;
        if (amount > 0 && allowance > 0) token.safeApprove(SAVINGS_CONTRACT, 0);
        token.safeApprove(SAVINGS_CONTRACT, amount);

        // Approve imUSD to the savings vault
        token = IERC20(SAVINGS_CONTRACT);
        allowance = token.allowance(address(this), SAVINGS_VAULT_CONTRACT);
        if (allowance == amount) return;
        if (amount > 0 && allowance > 0) token.safeApprove(SAVINGS_VAULT_CONTRACT, 0);
        token.safeApprove(SAVINGS_VAULT_CONTRACT, amount);
    }

    /**
     * @dev Deposits mUSD tokens to the mStable savings contract.
     * @param amount The amount of mUSD tokens to be deposited.
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        uint256 creditsIssued = _savingsContract.depositSavings(amount);
        require(creditsIssued > 0, "Error calling depositSavings on mStable savings contract: no credits issued.");
        _savingsVault.stake(creditsIssued);
    }

    /**
     * @dev Withdraws mUSD tokens from the mStable savings contract.
     * May withdraw slightly more than `amount` due to imperfect precision.
     * @param amount The amount of mUSD tokens to be withdrawn.
     */
    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        uint256 exchangeRate = _savingsContract.exchangeRate();
        uint256 credits = amount.mul(1e18).div(exchangeRate);
        if (credits.mul(exchangeRate).div(1e18) < amount) credits++; // Round up if necessary (i.e., if the division above left a remainder)
        _savingsVault.withdraw(credits);
        uint256 mAssetReturned = _savingsContract.redeem(credits);
        require(mAssetReturned > 0, "Error calling redeem on mStable savings contract: no mUSD returned.");
    }

    /**
     * @dev Withdraws all funds from the mStable savings contract.
     */
    function withdrawAll() external returns (bool) {
        uint256 creditBalance = _savingsVault.rawBalanceOf(address(this));
        if (creditBalance <= 0) return false;
        _savingsVault.withdraw(creditBalance);
        uint256 mAssetReturned = _savingsContract.redeem(creditBalance);
        require(mAssetReturned > 0, "Error calling redeem on mStable savings contract: no mUSD returned.");
        return true;
    }

    /**
     * @dev Claims mStable MTA rewards (if `all` is set, unlocks and claims locked rewards).
     * @param all If locked rewards should be unlocked and claimed.
     * @param first Index of the first array element to claim. Only applicable if `all` is true. Feed in the second value returned by the savings vault's `unclaimedRewards(address _account)` function.
     * @param last Index of the last array element to claim. Only applicable if `all` is true. Feed in the third value returned by the savings vault's `unclaimedRewards(address _account)` function.
     */
    function claimRewards(bool all, uint256 first, uint256 last) external {
        all ? _savingsVault.claimRewards(first, last) : _savingsVault.claimReward();
    }
}
