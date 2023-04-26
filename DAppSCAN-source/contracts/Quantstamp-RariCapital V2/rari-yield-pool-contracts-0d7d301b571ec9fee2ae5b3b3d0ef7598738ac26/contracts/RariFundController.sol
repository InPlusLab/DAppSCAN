/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public (i.e., non-administrative) application programming interfaces (APIs) of the official Ethereum smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license), provided that the application does not abuse the APIs or act against the interests of Rari Capital, Inc.
 * Anyone is free to study, review, and analyze the source code contained in this package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in this package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "@0x/contracts-exchange-libs/contracts/src/LibOrder.sol";

import "./RariFundManager.sol";
import "./lib/pools/DydxPoolController.sol";
import "./lib/pools/CompoundPoolController.sol";
import "./lib/pools/AavePoolController.sol";
import "./lib/pools/MStablePoolController.sol";
import "./lib/pools/YVaultPoolController.sol";
import "./lib/exchanges/ZeroExExchangeController.sol";
import "./lib/exchanges/MStableExchangeController.sol";

/**
 * @title RariFundController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice This contract handles deposits to and withdrawals from the liquidity pools that power the Rari Yield Pool as well as currency exchanges via 0x.
 */
contract RariFundController is Ownable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeERC20 for IERC20;

    /**
     * @dev Boolean to be checked on `upgradeFundController`.
     */
    bool public constant IS_RARI_FUND_CONTROLLER = true;

    /**
     * @dev Boolean that, if true, disables the primary functionality of this RariFundController.
     */
    bool public fundDisabled;

    /**
     * @dev Address of the RariFundManager.
     */
    address private _rariFundManagerContract;

    /**
     * @dev Contract of the RariFundManager.
     */
    RariFundManager public rariFundManager;

    /**
     * @dev Address of the rebalancer.
     */
    address private _rariFundRebalancerAddress;

    /**
     * @dev Array of currencies supported by the fund.
     */
    string[] private _supportedCurrencies;

    /**
     * @dev Maps `_supportedCurrencies` items to their indexes.
     */
    mapping(string => uint8) private _currencyIndexes;

    /**
     * @dev Maps supported currency codes to their decimal precisions (number of digits after the decimal point).
     */
    mapping(string => uint256) private _currencyDecimals;

    /**
     * @dev Maps supported currency codes to ERC20 token contract addresses.
     */
    mapping(string => address) private _erc20Contracts;

    /**
     * @dev Enum for liqudity pools supported by Rari.
     */
    enum LiquidityPool { dYdX, Compound, Aave, mStable, yVault }

    /**
     * @dev Maps currency codes to arrays of supported pools.
     */
    mapping(string => LiquidityPool[]) private _poolsByCurrency;

    /**
     * @dev Constructor that sets supported ERC20 contract addresses and supported pools for each supported token.
     */
    constructor () public {
        // Initialize base contracts
        Ownable.initialize(msg.sender);
        
        // Add supported currencies
        addSupportedCurrency("DAI", 0x6B175474E89094C44Da98b954EedeAC495271d0F, 18);
        addPoolToCurrency("DAI", LiquidityPool.dYdX);
        addPoolToCurrency("DAI", LiquidityPool.Compound);
        addPoolToCurrency("DAI", LiquidityPool.Aave);
        addPoolToCurrency("DAI", LiquidityPool.yVault);
        addSupportedCurrency("USDC", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 6);
        addPoolToCurrency("USDC", LiquidityPool.dYdX);
        addPoolToCurrency("USDC", LiquidityPool.Compound);
        addPoolToCurrency("USDC", LiquidityPool.Aave);
        addPoolToCurrency("USDC", LiquidityPool.yVault);
        addSupportedCurrency("USDT", 0xdAC17F958D2ee523a2206206994597C13D831ec7, 6);
        addPoolToCurrency("USDT", LiquidityPool.Compound);
        addPoolToCurrency("USDT", LiquidityPool.Aave);
        addPoolToCurrency("USDT", LiquidityPool.yVault);
        addSupportedCurrency("TUSD", 0x0000000000085d4780B73119b644AE5ecd22b376, 18);
        addPoolToCurrency("TUSD", LiquidityPool.Aave);
        addPoolToCurrency("TUSD", LiquidityPool.yVault);
        addSupportedCurrency("BUSD", 0x4Fabb145d64652a948d72533023f6E7A623C7C53, 18);
        addPoolToCurrency("BUSD", LiquidityPool.Aave);
        addSupportedCurrency("sUSD", 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51, 18);
        addPoolToCurrency("sUSD", LiquidityPool.Aave);
        addSupportedCurrency("mUSD", 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5, 18);
        addPoolToCurrency("mUSD", LiquidityPool.mStable);
    }

    /**
     * @dev Marks a token as supported by the fund and stores its decimal precision and ERC20 contract address.
     * @param currencyCode The currency code of the token.
     * @param erc20Contract The ERC20 contract address of the token.
     * @param decimals The decimal precision (number of digits after the decimal point) of the token.
     */
    function addSupportedCurrency(string memory currencyCode, address erc20Contract, uint256 decimals) internal {
        _currencyIndexes[currencyCode] = uint8(_supportedCurrencies.length);
        _supportedCurrencies.push(currencyCode);
        _erc20Contracts[currencyCode] = erc20Contract;
        _currencyDecimals[currencyCode] = decimals;
    }

    /**
     * @dev Adds a supported pool for a token.
     * @param currencyCode The currency code of the token.
     * @param pool Pool ID to be supported.
     */
    function addPoolToCurrency(string memory currencyCode, LiquidityPool pool) internal {
        _poolsByCurrency[currencyCode].push(pool);
    }

    /**
     * @dev Payable fallback function called by 0x Exchange v3 to refund unspent protocol fee.
     */
    function () external payable {
        require(msg.sender == 0x61935CbDd02287B511119DDb11Aeb42F1593b7Ef, "msg.sender is not 0x Exchange v3.");
    }

    /**
     * @dev Sets or upgrades RariFundController by withdrawing all tokens from all pools and forwarding them from the old to the new.
     * @param newContract The address of the new RariFundController contract.
     */
    function upgradeFundController(address payable newContract) external onlyOwner {
        require(fundDisabled, "This fund controller contract must be disabled before it can be upgraded.");
        require(RariFundController(newContract).IS_RARI_FUND_CONTROLLER(), "New contract does not have IS_RARI_FUND_CONTROLLER set to true.");

        for (uint256 i = 0; i < _supportedCurrencies.length; i++) {
            string memory currencyCode = _supportedCurrencies[i];

            for (uint256 j = 0; j < _poolsByCurrency[currencyCode].length; j++) if (hasCurrencyInPool(_poolsByCurrency[currencyCode][j], currencyCode)) {
                if (_poolsByCurrency[currencyCode][j] == LiquidityPool.yVault) YVaultPoolController.transferAll(_erc20Contracts[currencyCode], newContract);
                else _withdrawAllFromPool(_poolsByCurrency[currencyCode][j], currencyCode);
            }

            IERC20 token = IERC20(_erc20Contracts[currencyCode]);
            uint256 balance = token.balanceOf(address(this));
            if (balance > 0) token.safeTransfer(newContract, balance);
        }
    }

    /**
     * @dev Sets or upgrades RariFundController by forwarding tokens from the old to the new.
     * @param newContract The address of the new RariFundController contract.
     * @param erc20Contract The ERC20 contract address of the token to forward.
     * @return Boolean indicating if the balance transferred was greater than 0.
     */
    function upgradeFundController(address payable newContract, address erc20Contract) external onlyOwner returns (bool) {
        require(fundDisabled, "This fund controller contract must be disabled before it can be upgraded.");
        require(RariFundController(newContract).IS_RARI_FUND_CONTROLLER(), "New contract does not have IS_RARI_FUND_CONTROLLER set to true.");
        IERC20 token = IERC20(erc20Contract);
        uint256 balance = token.balanceOf(address(this));
        if (balance <= 0) return false;
        token.safeTransfer(newContract, balance);
        return true;
    }

    /**
     * @dev Checks funds in `currencyCode` in `pool` and updates `_poolsWithFunds`.
     * @param pool The index of the pool to check.
     * @param currencyCode The currency code of the token to check.
     * @return Boolean indicating if the fund controller has funds in `currencyCode` in `pool`.
     */
    function checkPoolForFunds(LiquidityPool pool, string calldata currencyCode) external returns (bool) {
        bool hasFunds = _getPoolBalance(pool, currencyCode) > 0;
        _poolsWithFunds[currencyCode][uint8(pool)] = hasFunds;
        return hasFunds;
    }

    /**
     * @dev Emitted when the RariFundManager of the RariFundController is set.
     */
    event FundManagerSet(address newAddress);

    /**
     * @dev Sets or upgrades the RariFundManager of the RariFundController.
     * @param newContract The address of the new RariFundManager contract.
     */
    function setFundManager(address newContract) external onlyOwner {
        // Approve maximum output tokens to RariFundManager
        for (uint256 i = 0; i < _supportedCurrencies.length; i++) {
            IERC20 token = IERC20(_erc20Contracts[_supportedCurrencies[i]]);
            if (_rariFundManagerContract != address(0)) token.safeApprove(_rariFundManagerContract, 0);
            if (newContract != address(0)) token.safeApprove(newContract, uint256(-1));
        }

        _rariFundManagerContract = newContract;
        rariFundManager = RariFundManager(_rariFundManagerContract);
        emit FundManagerSet(newContract);
    }

    /**
     * @dev Throws if called by any account other than the RariFundManager.
     */
    modifier onlyManager() {
        require(_rariFundManagerContract == msg.sender, "Caller is not the fund manager.");
        _;
    }

    /**
     * @dev Emitted when the rebalancer of the RariFundController is set.
     */
    event FundRebalancerSet(address newAddress);

    /**
     * @dev Sets or upgrades the rebalancer of the RariFundController.
     * @param newAddress The Ethereum address of the new rebalancer server.
     */
    function setFundRebalancer(address newAddress) external onlyOwner {
        _rariFundRebalancerAddress = newAddress;
        emit FundRebalancerSet(newAddress);
    }

    /**
     * @dev Throws if called by any account other than the rebalancer.
     */
    modifier onlyRebalancer() {
        require(_rariFundRebalancerAddress == msg.sender, "Caller is not the rebalancer.");
        _;
    }

    /**
     * @dev Emitted when the primary functionality of this RariFundController contract has been disabled.
     */
    event FundDisabled();

    /**
     * @dev Emitted when the primary functionality of this RariFundController contract has been enabled.
     */
    event FundEnabled();

    /**
     * @dev Disables/enables primary functionality of this RariFundController so contract(s) can be upgraded.
     */
    function setFundDisabled(bool disabled) external onlyOwner {
        require(disabled != fundDisabled, "No change to fund enabled/disabled status.");
        fundDisabled = disabled;
        if (disabled) emit FundDisabled(); else emit FundEnabled();
    }

    /**
     * @dev Throws if fund is disabled.
     */
    modifier fundEnabled() {
        require(!fundDisabled, "This fund controller contract is disabled. This may be due to an upgrade.");
        _;
    }

    /**
     * @dev Returns `_poolsByCurrency[currencyCode]`. Used by `RariFundProxy.getRawFundBalancesAndPrices`.
     */
    function getPoolsByCurrency(string calldata currencyCode) external view returns (LiquidityPool[] memory) {
        return _poolsByCurrency[currencyCode];
    }

    /**
     * @dev Returns the balances of all currencies supported by dYdX.
     * @return An array of ERC20 token contract addresses and a corresponding array of balances.
     */
    function getDydxBalances() external view returns (address[] memory, uint256[] memory) {
        return DydxPoolController.getBalances();
    }

    /**
     * @dev Returns the fund controller's balance of the specified currency in the specified pool (without checking `_poolsWithFunds` first).
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `CompoundPoolController.getBalance`) potentially modifies the state.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token.
     */
    function _getPoolBalance(LiquidityPool pool, string memory currencyCode) public returns (uint256) {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == LiquidityPool.dYdX) return DydxPoolController.getBalance(erc20Contract);
        else if (pool == LiquidityPool.Compound) return CompoundPoolController.getBalance(erc20Contract);
        else if (pool == LiquidityPool.Aave) return AavePoolController.getBalance(erc20Contract);
        else if (pool == LiquidityPool.mStable && erc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) return MStablePoolController.getBalance();
        else if (pool == LiquidityPool.yVault) return YVaultPoolController.getBalance(erc20Contract);
        else revert("Invalid pool index.");
    }

    /**
     * @dev Returns the fund controller's balance of the specified currency in the specified pool (checking `_poolsWithFunds` first to save gas).
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `CompoundPoolController.getBalance`) potentially modifies the state.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token.
     */
    function getPoolBalance(LiquidityPool pool, string memory currencyCode) public returns (uint256) {
        if (!_poolsWithFunds[currencyCode][uint8(pool)]) return 0;
        return _getPoolBalance(pool, currencyCode);
    }

    /**
     * @dev Approves tokens to the specified pool without spending gas on every deposit.
     * Note that this function is vulnerable to the allowance double-spend exploit, as with the `approve` functions of the ERC20 contracts themselves. If you are concerned and setting exact allowances, make sure to set allowance to 0 on the client side before setting an allowance greater than 0.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be approved.
     * @param amount The amount of tokens to be approved.
     */
    function approveToPool(LiquidityPool pool, string calldata currencyCode, uint256 amount) external fundEnabled onlyRebalancer {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == LiquidityPool.dYdX) DydxPoolController.approve(erc20Contract, amount);
        else if (pool == LiquidityPool.Compound) CompoundPoolController.approve(erc20Contract, amount);
        else if (pool == LiquidityPool.Aave) AavePoolController.approve(erc20Contract, amount);
        else if (pool == LiquidityPool.mStable && erc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) return MStablePoolController.approve(amount);
        else if (pool == LiquidityPool.yVault) YVaultPoolController.approve(erc20Contract, amount);
        else revert("Invalid pool index.");
    }

    /**
     * @dev Mapping of bools indicating the presence of funds to pool indexes to currency codes.
     */
    mapping(string => mapping(uint8 => bool)) _poolsWithFunds;

    /**
     * @dev Return a boolean indicating if the fund controller has funds in `currencyCode` in `pool`.
     * @param pool The index of the pool to check.
     * @param currencyCode The currency code of the token to check.
     */
    function hasCurrencyInPool(LiquidityPool pool, string memory currencyCode) public view returns (bool) {
        return _poolsWithFunds[currencyCode][uint8(pool)];
    }

    /**
     * @dev Referral code for Aave deposits.
     */
    uint16 _aaveReferralCode;

    /**
     * @dev Sets the referral code for Aave deposits.
     * @param referralCode The referral code.
     */
    function setAaveReferralCode(uint16 referralCode) external onlyOwner {
        _aaveReferralCode = referralCode;
    }

    /**
     * @dev Enum for pool allocation action types supported by Rari.
     */
    enum PoolAllocationAction { Deposit, Withdraw, WithdrawAll }

    /**
     * @dev Emitted when a deposit or withdrawal is made.
     * Note that `amount` is not set for `WithdrawAll` actions.
     */
    event PoolAllocation(PoolAllocationAction indexed action, LiquidityPool indexed pool, string indexed currencyCode, uint256 amount);

    /**
     * @dev Deposits funds to the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     */
    function depositToPool(LiquidityPool pool, string calldata currencyCode, uint256 amount) external fundEnabled onlyRebalancer {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == LiquidityPool.dYdX) DydxPoolController.deposit(erc20Contract, amount);
        else if (pool == LiquidityPool.Compound) CompoundPoolController.deposit(erc20Contract, amount);
        else if (pool == LiquidityPool.Aave) AavePoolController.deposit(erc20Contract, amount, _aaveReferralCode);
        else if (pool == LiquidityPool.mStable && erc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) MStablePoolController.deposit(amount);
        else if (pool == LiquidityPool.yVault) YVaultPoolController.deposit(erc20Contract, amount);
        else revert("Invalid pool index.");
        _poolsWithFunds[currencyCode][uint8(pool)] = true;
        emit PoolAllocation(PoolAllocationAction.Deposit, pool, currencyCode, amount);
    }

    /**
     * @dev Internal function to withdraw funds from the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     */
    function _withdrawFromPool(LiquidityPool pool, string memory currencyCode, uint256 amount) internal {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == LiquidityPool.dYdX) DydxPoolController.withdraw(erc20Contract, amount);
        else if (pool == LiquidityPool.Compound) CompoundPoolController.withdraw(erc20Contract, amount);
        else if (pool == LiquidityPool.Aave) AavePoolController.withdraw(erc20Contract, amount);
        else if (pool == LiquidityPool.mStable && erc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) MStablePoolController.withdraw(amount);
        else if (pool == LiquidityPool.yVault) YVaultPoolController.withdraw(erc20Contract, amount);
        else revert("Invalid pool index.");
        emit PoolAllocation(PoolAllocationAction.Withdraw, pool, currencyCode, amount);
    }

    /**
     * @dev Withdraws funds from the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     */
    function withdrawFromPool(LiquidityPool pool, string calldata currencyCode, uint256 amount) external fundEnabled onlyRebalancer {
        _withdrawFromPool(pool, currencyCode, amount);
        _poolsWithFunds[currencyCode][uint8(pool)] = _getPoolBalance(pool, currencyCode) > 0;
    }

    /**
     * @dev Withdraws funds from the specified pool (with optimizations based on the `all` parameter).
     * If we already know all funds are being withdrawn, we won't have to check again here in this function. 
     * If withdrawing all funds, we choose _withdrawFromPool or _withdrawAllFromPool based on estimated gas usage.
     * The value of `all` is trusted because `msg.sender` is always RariFundManager.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     * @param all Boolean indicating if all funds are being withdrawn.
     */
    function withdrawFromPoolOptimized(LiquidityPool pool, string calldata currencyCode, uint256 amount, bool all) external fundEnabled onlyManager {
        all && (pool == LiquidityPool.dYdX || pool == LiquidityPool.mStable || pool == LiquidityPool.yVault) ? _withdrawAllFromPool(pool, currencyCode) : _withdrawFromPool(pool, currencyCode, amount);
        if (all) _poolsWithFunds[currencyCode][uint8(pool)] = false;
    }

    /**
     * @dev Internal function to withdraw all funds from the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The ERC20 contract of the token to be withdrawn.
     */
    function _withdrawAllFromPool(LiquidityPool pool, string memory currencyCode) internal {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == LiquidityPool.dYdX) DydxPoolController.withdrawAll(erc20Contract);
        else if (pool == LiquidityPool.Compound) require(CompoundPoolController.withdrawAll(erc20Contract), "No Compound balance to withdraw from.");
        else if (pool == LiquidityPool.Aave) require(AavePoolController.withdrawAll(erc20Contract), "No Aave balance to withdraw from.");
        else if (pool == LiquidityPool.mStable && erc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) require(MStablePoolController.withdrawAll(), "No mStable balance to withdraw from.");
        else if (pool == LiquidityPool.yVault) require(YVaultPoolController.withdrawAll(erc20Contract), "No yVault balance to withdraw from.");
        else revert("Invalid pool index.");
        _poolsWithFunds[currencyCode][uint8(pool)] = false;
        emit PoolAllocation(PoolAllocationAction.WithdrawAll, pool, currencyCode, 0);
    }

    /**
     * @dev Withdraws all funds from the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The ERC20 contract of the token to be withdrawn.
    */
    function withdrawAllFromPool(LiquidityPool pool, string calldata currencyCode) external fundEnabled onlyRebalancer {
        _withdrawAllFromPool(pool, currencyCode);
    }

    /**
     * @dev Withdraws all funds from the specified pool (without requiring the fund to be enabled).
     * @param pool The index of the pool.
     * @param currencyCode The ERC20 contract of the token to be withdrawn.
     */
    function withdrawAllFromPoolOnUpgrade(LiquidityPool pool, string calldata currencyCode) external onlyOwner {
        _withdrawAllFromPool(pool, currencyCode);
    }

    /**
     * @dev Approves tokens to 0x without spending gas on every deposit.
     * Note that this function is vulnerable to the allowance double-spend exploit, as with the `approve` functions of the ERC20 contracts themselves. If you are concerned and setting exact allowances, make sure to set allowance to 0 on the client side before setting an allowance greater than 0.
     * @param erc20Contract The ERC20 contract address of the token to be approved.
     * @param amount The amount of tokens to be approved.
     */
    function approveTo0x(address erc20Contract, uint256 amount) external fundEnabled onlyRebalancer {
        ZeroExExchangeController.approve(erc20Contract, amount);
    }

    /**
     * @dev Enum for currency exchanges supported by Rari.
     */
    enum CurrencyExchange { ZeroEx, mStable }

    /**
     * @dev Emitted when currencies are exchanged via 0x or mStable.
     * Note that `inputAmountUsd` and `outputAmountUsd` are not present when the input currency is not a supported stablecoin (i.e., when exchanging COMP via 0x).
     */
    event CurrencyTrade(string indexed inputCurrencyCode, string indexed outputCurrencyCode, uint256 inputAmount, uint256 inputAmountUsd, uint256 outputAmount, uint256 outputAmountUsd, CurrencyExchange indexed exchange);

    /**
     * @dev Daily limit on 0x exchange order slippage (scaled by 1e18).
     */
    uint256 private _dailyLossRateLimit;

    /**
     * @dev Sets or upgrades the daily limit on 0x exchange order loss over raw total fund balance.
     * @param limit The daily limit on 0x exchange order loss over raw total fund balance (scaled by 1e18).
     */
    function setDailyLossRateLimit(uint256 limit) external onlyOwner {
        _dailyLossRateLimit = limit;
    }

    /**
     * @dev Struct for a loss of funds due to a currency exchange (loss could be negative).
     */
    struct CurrencyExchangeLoss {
        uint256 timestamp;
        int256 lossRate;
    }

    /**
     * @dev Array of arrays containing 0x exchange order time and slippage (scaled by 1e18).
     */
    CurrencyExchangeLoss[] private _lossRateHistory;

    /**
     * @dev Market sell to 0x exchange orders (reverting if `takerAssetFillAmount` is not filled or the 24-hour slippage limit is surpassed).
     * We should be able to make this function external and use calldata for all parameters, but Solidity does not support calldata structs (https://github.com/ethereum/solidity/issues/5479).
     * @param inputCurrencyCode The currency code of the token to be sold.
     * @param outputCurrencyCode The currency code of the token to be bought.
     * @param orders The limit orders to be filled in ascending order of price.
     * @param signatures The signatures for the orders.
     * @param takerAssetFillAmount The amount of the taker asset to sell (excluding taker fees).
     */
    function marketSell0xOrdersFillOrKill(string memory inputCurrencyCode, string memory outputCurrencyCode, LibOrder.Order[] memory orders, bytes[] memory signatures, uint256 takerAssetFillAmount) public payable fundEnabled onlyRebalancer {
        // Check if input is a supported stablecoin and make sure output is a supported stablecoin
        address inputErc20Contract = _erc20Contracts[inputCurrencyCode];
        address outputErc20Contract = _erc20Contracts[outputCurrencyCode];
        require(outputErc20Contract != address(0), "Invalid output currency code.");

        // Check orders (if inputting a supported stablecoin)
        if (inputErc20Contract != address(0)) for (uint256 i = 0; i < orders.length; i++) {
            address takerAssetAddress = ZeroExExchangeController.decodeTokenAddress(orders[i].takerAssetData);
            require(inputErc20Contract == takerAssetAddress, "Not all input assets correspond to input currency code.");
            address makerAssetAddress = ZeroExExchangeController.decodeTokenAddress(orders[i].makerAssetData);
            require(outputErc20Contract == makerAssetAddress, "Not all output assets correspond to output currency code.");
            if (orders[i].takerFee > 0) require(orders[i].takerFeeAssetData.length == 0, "Taker fees are not supported."); // TODO: Support orders with taker fees (need to include taker fees in loss calculation)
        }

        // Get prices and raw fund balance before exchange
        uint256[] memory pricesInUsd;
        uint256 rawFundBalanceBeforeExchange;

        if (inputErc20Contract != address(0)) {
            pricesInUsd = rariFundManager.rariFundPriceConsumer().getCurrencyPricesInUsd();
            rawFundBalanceBeforeExchange = rariFundManager.getRawFundBalance(pricesInUsd);
        }

        // Market sell
        uint256[2] memory filledAmounts = ZeroExExchangeController.marketSellOrdersFillOrKill(orders, signatures, takerAssetFillAmount, msg.value);

        // Check 24-hour loss rate limit (if inputting a supported stablecoin)
        uint256 inputFilledAmountUsd = 0;
        uint256 outputFilledAmountUsd = 0;

        if (inputErc20Contract != address(0)) {
            inputFilledAmountUsd = toUsd(inputCurrencyCode, filledAmounts[0], pricesInUsd);
            outputFilledAmountUsd = toUsd(inputCurrencyCode, filledAmounts[1], pricesInUsd);
            handleExchangeLoss(inputFilledAmountUsd, outputFilledAmountUsd, rawFundBalanceBeforeExchange);
        }

        // Emit event
        emit CurrencyTrade(inputCurrencyCode, outputCurrencyCode, filledAmounts[0], inputFilledAmountUsd, filledAmounts[1], outputFilledAmountUsd, CurrencyExchange.ZeroEx);

        // Refund unused ETH
        uint256 ethBalance = address(this).balance;
        
        if (ethBalance > 0) {
            (bool success, ) = msg.sender.call.value(ethBalance)("");
            require(success, "Failed to transfer ETH to msg.sender after exchange.");
        }
    }

    /**
     * @dev Converts an amount to USD (scaled by 1e18).
     * @param currencyCode The currency code to convert.
     * @param amount The amount to convert.
     * @param pricesInUsd An array of prices in USD for all supported currencies (in order).
     * @return The equivalent USD amount (scaled by 1e18).
     */
    function toUsd(string memory currencyCode, uint256 amount, uint256[] memory pricesInUsd) internal view returns (uint256) {
        return amount.mul(pricesInUsd[_currencyIndexes[currencyCode]]).div(10 ** _currencyDecimals[currencyCode]);
    }

    /**
     * @dev Checks the validity of a trade given the 24-hour exchange loss rate limit; if breached, reverts; otherwise, logs the loss rate of the trade.
     * Note that while miners may be able to manipulate `block.timestamp` by up to 900 seconds, this small margin of error is acceptable.
     * @param inputAmountUsd The amount sold in USD (scaled by 1e18).
     * @param outputAmountUsd The amount bought in USD (scaled by 1e18).
     */
    function handleExchangeLoss(uint256 inputAmountUsd, uint256 outputAmountUsd, uint256 rawFundBalanceBeforeExchange) internal {
        // Calculate loss rate
        int256 lossUsd = int256(inputAmountUsd).sub(int256(outputAmountUsd));
        int256 lossRate = lossUsd.mul(1e18).div(int256(rawFundBalanceBeforeExchange));

        // Check if sum of loss rates over the last 24 hours + this trade's loss rate > the limit
        int256 lossRateLastDay = 0;

        for (uint256 i = _lossRateHistory.length; i > 0; i--) {
            if (_lossRateHistory[i - 1].timestamp < block.timestamp.sub(86400)) break;
            lossRateLastDay = lossRateLastDay.add(_lossRateHistory[i - 1].lossRate);
        }

        require(lossRateLastDay.add(lossRate) <= int256(_dailyLossRateLimit), "This exchange would violate the 24-hour loss rate limit.");

        // Log loss rate in history
        _lossRateHistory.push(CurrencyExchangeLoss(block.timestamp, lossRate));
    }

    /**
     * @dev Approves tokens to the mUSD token contract without spending gas on every deposit.
     * Note that this function is vulnerable to the allowance double-spend exploit, as with the `approve` functions of the ERC20 contracts themselves. If you are concerned and setting exact allowances, make sure to set allowance to 0 on the client side before setting an allowance greater than 0.
     * @param currencyCode The currency code of the token to be approved.
     * @param amount Amount of the specified token to approve to the mUSD token contract.
     */
    function approveToMUsd(string calldata currencyCode, uint256 amount) external fundEnabled onlyRebalancer {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        MStableExchangeController.approve(erc20Contract, amount);
    }

    /**
     * @dev Swaps tokens via mStable mUSD.
     * @param inputCurrencyCode The currency code of the input token to be sold.
     * @param outputCurrencyCode The currency code of the output token to be bought.
     * @param inputAmount The amount of input tokens to be sold.
     */
    function swapMStable(string calldata inputCurrencyCode, string calldata outputCurrencyCode, uint256 inputAmount) external fundEnabled onlyRebalancer {
        // Input validation
        address inputErc20Contract = _erc20Contracts[inputCurrencyCode];
        address outputErc20Contract = _erc20Contracts[outputCurrencyCode];
        require(outputErc20Contract != address(0), "Invalid input currency code.");
        require(inputErc20Contract != address(0), "Invalid output currency code.");

        // Get prices and raw fund balance before exchange
        uint256[] memory pricesInUsd;
        uint256 rawFundBalanceBeforeExchange;
        pricesInUsd = rariFundManager.rariFundPriceConsumer().getCurrencyPricesInUsd();
        rawFundBalanceBeforeExchange = rariFundManager.getRawFundBalance(pricesInUsd);

        // Swap stablecoins via mUSD
        uint256 outputAmount;

        if (inputErc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) {
            uint256 outputDecimals = _currencyDecimals[outputCurrencyCode];
            uint256 outputAmountBeforeFees = outputDecimals >= 18 ? inputAmount.mul(10 ** outputDecimals.sub(18)) : inputAmount.div(10 ** uint256(18).sub(outputDecimals));
            uint256 mUsdRedeemed = MStableExchangeController.redeem(outputErc20Contract, outputAmountBeforeFees);
            require(mUsdRedeemed == inputAmount, "Amount of mUSD redeemed not equal to input mUSD amount.");
            outputAmount = outputAmountBeforeFees.sub(outputAmountBeforeFees.mul(MStableExchangeController.getSwapFee()).div(1e18));
        } else if (outputErc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) outputAmount = MStableExchangeController.mint(inputErc20Contract, inputAmount);
        else outputAmount = MStableExchangeController.swap(inputErc20Contract, outputErc20Contract, inputAmount);

        // Check 24-hour loss rate limit
        uint256 inputFilledAmountUsd = toUsd(inputCurrencyCode, inputAmount, pricesInUsd);
        uint256 outputFilledAmountUsd = toUsd(outputCurrencyCode, outputAmount, pricesInUsd);
        handleExchangeLoss(inputFilledAmountUsd, outputFilledAmountUsd, rawFundBalanceBeforeExchange);

        // Emit event
        emit CurrencyTrade(inputCurrencyCode, outputCurrencyCode, inputAmount, inputFilledAmountUsd, outputAmount, outputFilledAmountUsd, CurrencyExchange.mStable);
    }
}
