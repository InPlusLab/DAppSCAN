/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public APIs (described in `API.md` of the `rari-contracts` package) of the official smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license) benefitting Rari Capital, Inc.
 * Only those with explicit permission from a co-founder of Rari Capital (Jai Bhavnani, Jack Lipstone, or David Lucid) are permitted to study, review, or analyze any part of the source code contained in the `rari-contracts` package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in the `rari-contracts` package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity ^0.5.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@0x/contracts-exchange-libs/contracts/src/LibOrder.sol";

import "./RariFundManager.sol";
import "./lib/pools/DydxPoolController.sol";
import "./lib/pools/CompoundPoolController.sol";
import "./lib/pools/AavePoolController.sol";
import "./lib/exchanges/ZeroExExchangeController.sol";

/**
 * @title RariFundController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice This contract handles deposits to and withdrawals from the liquidity pools that power RariFund as well as currency exchanges via 0x.
 */
contract RariFundController is Ownable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeERC20 for IERC20;

    /**
     * @notice Package version of `rari-contracts` when this contract was deployed.
     */
    string public constant VERSION = "2.0.0";

    /**
     * @dev Boolean that, if true, disables the primary functionality of this RariFundController.
     */
    bool private _fundDisabled;

    /**
     * @dev Address of the RariFundManager.
     */
    address private _rariFundManagerContract;

    /**
     * @dev Contract of the RariFundManager.
     */
    RariFundManager private _rariFundManager;

    /**
     * @dev Address of the rebalancer.
     */
    address private _rariFundRebalancerAddress;

    /**
     * @dev Array of currencies supported by the fund.
     */
    string[] private _supportedCurrencies;

    /**
     * @dev Maps decimal precisions (number of digits after the decimal point) to supported currency codes.
     */
    mapping(string => uint256) private _currencyDecimals;

    /**
     * @dev Maps ERC20 token contract addresses to supported currency codes.
     */
    mapping(string => address) private _erc20Contracts;

    /**
     * @dev Maps arrays of supported pools to currency codes.
     */
    mapping(string => uint8[]) private _poolsByCurrency;

    /**
     * @dev Constructor that sets supported ERC20 token contract addresses and supported pools for each supported token.
     */
    constructor () public {
        // Add supported currencies
        addSupportedCurrency("DAI", 0x6B175474E89094C44Da98b954EedeAC495271d0F, 18);
        addPoolToCurrency("DAI", 0); // dYdX
        addPoolToCurrency("DAI", 1); // Compound
        addPoolToCurrency("DAI", 2); // Aave
        addSupportedCurrency("USDC", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 6);
        addPoolToCurrency("USDC", 0); // dYdX
        addPoolToCurrency("USDC", 1); // Compound
        addPoolToCurrency("USDC", 2); // Aave
        addSupportedCurrency("USDT", 0xdAC17F958D2ee523a2206206994597C13D831ec7, 6);
        addPoolToCurrency("USDT", 1); // Compound
        addPoolToCurrency("USDT", 2); // Aave
        addSupportedCurrency("TUSD", 0x0000000000085d4780B73119b644AE5ecd22b376, 18);
        addPoolToCurrency("TUSD", 2); // Aave
        addSupportedCurrency("BUSD", 0x4Fabb145d64652a948d72533023f6E7A623C7C53, 18);
        addPoolToCurrency("BUSD", 2); // Aave
        addSupportedCurrency("sUSD", 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51, 18);
        addPoolToCurrency("sUSD", 2); // Aave
    }

    /**
     * @dev Marks a token as supported by the fund and stores its decimal precision and ERC20 contract address.
     * @param currencyCode The currency code of the token.
     * @param erc20Contract The ERC20 contract address of the token.
     * @param decimals The decimal precision (number of digits after the decimal point) of the token.
     */
    function addSupportedCurrency(string memory currencyCode, address erc20Contract, uint256 decimals) internal {
        _supportedCurrencies.push(currencyCode);
        _erc20Contracts[currencyCode] = erc20Contract;
        _currencyDecimals[currencyCode] = decimals;
    }

    /**
     * @dev Adds a supported pool for a token.
     * @param currencyCode The currency code of the token.
     * @param pool Pool ID to be supported.
     */
    function addPoolToCurrency(string memory currencyCode, uint8 pool) internal {
        _poolsByCurrency[currencyCode].push(pool);
    }

    /**
     * @dev Payable fallback function called by 0x exchange to refund unspent protocol fee.
     */
    function () external payable { }

    /**
     * @dev Sets or upgrades RariFundController by withdrawing all tokens from all pools and forwarding them from the old to the new.
     * @param newContract The address of the new RariFundController contract.
     */
    function upgradeFundController(address payable newContract) external onlyOwner {
        for (uint256 i = 0; i < _supportedCurrencies.length; i++) {
            string memory currencyCode = _supportedCurrencies[i];

            for (uint256 j = 0; j < _poolsByCurrency[currencyCode].length; j++)
                if (hasCurrencyInPool(_poolsByCurrency[currencyCode][j], currencyCode))
                    _withdrawAllFromPool(_poolsByCurrency[currencyCode][j], currencyCode);

            IERC20 token = IERC20(_erc20Contracts[currencyCode]);
            uint256 balance = token.balanceOf(address(this));
            if (balance > 0) token.safeTransfer(newContract, balance);
        }
    }

    /**
     * @dev Sets or upgrades RariFundController by forwarding tokens from the old to the new.
     * @param newContract The address of the new RariFundController contract.
     * @param erc20Contract The ERC20 contract address of the token to forward.
     */
    function upgradeFundController(address payable newContract, address erc20Contract) external onlyOwner returns (bool) {
        IERC20 token = IERC20(erc20Contract);
        uint256 balance = token.balanceOf(address(this));
        if (balance <= 0) return false;
        token.safeTransfer(newContract, balance);
        return true;
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
        _rariFundManager = RariFundManager(_rariFundManagerContract);
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
     * @dev Disables primary functionality of this RariFundController so contract(s) can be upgraded.
     */
    function disableFund() external onlyOwner {
        require(!_fundDisabled, "Fund already disabled.");
        _fundDisabled = true;
        emit FundDisabled();
    }

    /**
     * @dev Enables primary functionality of this RariFundController once contract(s) are upgraded.
     */
    function enableFund() external onlyOwner {
        require(_fundDisabled, "Fund already enabled.");
        _fundDisabled = false;
        emit FundEnabled();
    }

    /**
     * @dev Throws if fund is disabled.
     */
    modifier fundEnabled() {
        require(!_fundDisabled, "This fund controller contract is disabled. This may be due to an upgrade.");
        _;
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
     * @dev Ideally, we can add the view modifier, but Compound's `getUnderlyingBalance` function (called by `CompoundPoolController.getBalance`) potentially modifies the state.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token.
     */
    function _getPoolBalance(uint8 pool, string memory currencyCode) public returns (uint256) {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == 0) return DydxPoolController.getBalance(erc20Contract);
        else if (pool == 1) return CompoundPoolController.getBalance(erc20Contract);
        else if (pool == 2) return AavePoolController.getBalance(erc20Contract);
        else revert("Invalid pool index.");
    }

    /**
     * @dev Returns the fund controller's balance of the specified currency in the specified pool (checking `_poolsWithFunds` first to save gas).
     * @dev Ideally, we can add the view modifier, but Compound's `getUnderlyingBalance` function (called by `CompoundPoolController.getBalance`) potentially modifies the state.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token.
     */
    function getPoolBalance(uint8 pool, string memory currencyCode) public returns (uint256) {
        if (!_poolsWithFunds[currencyCode][pool]) return 0;
        return _getPoolBalance(pool, currencyCode);
    }

    /**
     * @notice Returns the fund controller's contract balance of each currency and balance of each pool of each currency (checking `_poolsWithFunds` first to save gas).
     * @dev Ideally, we can add the view modifier, but Compound's `getUnderlyingBalance` function (called by `getPoolBalance`) potentially modifies the state.
     * @return An array of currency codes, an array of corresponding fund controller contract balances for each currency code, an array of arrays of pool indexes for each currency code, and an array of arrays of corresponding balances at each pool index for each currency code.
     */
    function getAllBalances() external returns (string[] memory, uint256[] memory, uint256[][] memory, uint256[][] memory) {
        uint256[] memory contractBalances = new uint256[](_supportedCurrencies.length);
        uint256[][] memory pools = new uint256[][](_supportedCurrencies.length);
        uint256[][] memory poolBalances = new uint256[][](_supportedCurrencies.length);

        for (uint256 i = 0; i < _supportedCurrencies.length; i++) {
            string memory currencyCode = _supportedCurrencies[i];
            contractBalances[i] = IERC20(_erc20Contracts[currencyCode]).balanceOf(address(this));
            pools[i] = new uint256[](_poolsByCurrency[currencyCode].length);
            poolBalances[i] = new uint256[](_poolsByCurrency[currencyCode].length);

            for (uint256 j = 0; j < _poolsByCurrency[currencyCode].length; j++) {
                pools[i][j] = _poolsByCurrency[currencyCode][j];
                poolBalances[i][j] = getPoolBalance(_poolsByCurrency[currencyCode][j], currencyCode);
            }
        }

        return (_supportedCurrencies, contractBalances, pools, poolBalances);
    }

    /**
     * @dev Approves tokens to the specified pool without spending gas on every deposit.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be approved.
     * @param amount The amount of tokens to be approved.
     */
    function approveToPool(uint8 pool, string calldata currencyCode, uint256 amount) external fundEnabled onlyRebalancer {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == 0) DydxPoolController.approve(erc20Contract, amount);
        else if (pool == 1) CompoundPoolController.approve(erc20Contract, amount);
        else if (pool == 2) AavePoolController.approve(erc20Contract, amount);
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
    function hasCurrencyInPool(uint8 pool, string memory currencyCode) public view returns (bool) {
        return _poolsWithFunds[currencyCode][pool];
    }

    /**
     * @dev Referral code for Aave deposits.
     */
    uint16 _aaveReferralCode = 86;

    /**
     * @dev Sets the referral code for Aave deposits.
     * @param referralCode The referral code.
     */
    function setAaveReferralCode(uint16 referralCode) external onlyOwner {
        _aaveReferralCode = referralCode;
    }

    /**
     * @dev Deposits funds to the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     */
    function depositToPool(uint8 pool, string calldata currencyCode, uint256 amount) external fundEnabled onlyRebalancer {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == 0) DydxPoolController.deposit(erc20Contract, amount);
        else if (pool == 1) CompoundPoolController.deposit(erc20Contract, amount);
        else if (pool == 2) AavePoolController.deposit(erc20Contract, amount, _aaveReferralCode);
        else revert("Invalid pool index.");
        _poolsWithFunds[currencyCode][pool] = true;
    }

    /**
     * @dev Internal function to withdraw funds from the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     */
    function _withdrawFromPool(uint8 pool, string memory currencyCode, uint256 amount) internal {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == 0) DydxPoolController.withdraw(erc20Contract, amount);
        else if (pool == 1) CompoundPoolController.withdraw(erc20Contract, amount);
        else if (pool == 2) AavePoolController.withdraw(erc20Contract, amount);
        else revert("Invalid pool index.");
    }

    /**
     * @dev Withdraws funds from the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     */
    function withdrawFromPool(uint8 pool, string calldata currencyCode, uint256 amount) external fundEnabled onlyRebalancer {
        _withdrawFromPool(pool, currencyCode, amount);
        _poolsWithFunds[currencyCode][pool] = _getPoolBalance(pool, currencyCode) > 0;
    }

    /**
     * @dev Withdraws funds from the specified pool (caching the `initialBalance` parameter).
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     * @param initialBalance The fund's balance of the specified currency in the specified pool before the withdrawal.
     */
    function withdrawFromPoolKnowingBalance(uint8 pool, string calldata currencyCode, uint256 amount, uint256 initialBalance) external fundEnabled onlyManager {
        _withdrawFromPool(pool, currencyCode, amount);
        if (amount == initialBalance) _poolsWithFunds[currencyCode][pool] = false;
    }

    /**
     * @dev Internal function to withdraw all funds from the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The ERC20 contract of the token to be withdrawn.
     */
    function _withdrawAllFromPool(uint8 pool, string memory currencyCode) internal {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == 0) DydxPoolController.withdrawAll(erc20Contract);
        else if (pool == 1) require(CompoundPoolController.withdrawAll(erc20Contract), "No Compound balance to withdraw from.");
        else if (pool == 2) require(AavePoolController.withdrawAll(erc20Contract), "No Aave balance to withdraw from.");
        else revert("Invalid pool index.");
        _poolsWithFunds[currencyCode][pool] = false;
    }

    /**
     * @dev Withdraws all funds from the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The ERC20 contract of the token to be withdrawn.
    */
    function withdrawAllFromPool(uint8 pool, string calldata currencyCode) external fundEnabled onlyRebalancer {
        _withdrawAllFromPool(pool, currencyCode);
    }

    /**
     * @dev Withdraws all funds from the specified pool (without requiring the fund to be enabled).
     * @param pool The index of the pool.
     * @param currencyCode The ERC20 contract of the token to be withdrawn.
     */
    function withdrawAllFromPoolOnUpgrade(uint8 pool, string calldata currencyCode) external onlyOwner {
        _withdrawAllFromPool(pool, currencyCode);
    }

    /**
     * @dev Approves tokens to 0x without spending gas on every deposit.
     * @param erc20Contract The ERC20 contract address of the token to be approved.
     * @param amount The amount of tokens to be approved.
     * @return Boolean indicating success.
     */
    function approveTo0x(address erc20Contract, uint256 amount) external fundEnabled onlyRebalancer {
        ZeroExExchangeController.approve(erc20Contract, amount);
    }

    /**
     * @dev Emitted when currencies are exchanged via 0x.
     */
    event CurrencyExchange(string inputCurrencyCode, string outputCurrencyCode);

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

        // Market sell
        uint256[2] memory filledAmounts = ZeroExExchangeController.marketSellOrdersFillOrKill(orders, signatures, takerAssetFillAmount, msg.value);

        // Check 24-hour loss rate limit (if inputting a supported stablecoin)
        if (inputErc20Contract != address(0)) {
            uint256 inputDecimals = _currencyDecimals[inputCurrencyCode];
            uint256 inputFilledAmountUsd = 18 >= inputDecimals ? filledAmounts[0].mul(10 ** (uint256(18).sub(inputDecimals))) : filledAmounts[0].div(10 ** (inputDecimals.sub(18))); // TODO: Factor in prices; for now we assume the value of all supported currencies = $1
            uint256 outputDecimals = _currencyDecimals[outputCurrencyCode];
            uint256 outputFilledAmountUsd = 18 >= outputDecimals ? filledAmounts[1].mul(10 ** (uint256(18).sub(outputDecimals))) : filledAmounts[1].div(10 ** (outputDecimals.sub(18))); // TODO: Factor in prices; for now we assume the value of all supported currencies = $1
            int256 lossUsd = int256(inputFilledAmountUsd).sub(int256(outputFilledAmountUsd));
            int256 lossRate = lossUsd.mul(1e18).div(int256(_rariFundManager.getRawFundBalance()));
            require(checkLossRateLimit(lossRate), "This exchange would violate the 24-hour loss rate limit.");
            _lossRateHistory.push(CurrencyExchangeLoss(block.timestamp, lossRate));
        }

        // Emit event
        emit CurrencyExchange(inputCurrencyCode, outputCurrencyCode);

        // Refund unused ETH
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) msg.sender.transfer(ethBalance);
    }

    /**
     * @dev Checks the 24-hour loss rate limit.
     * This function was separated from the `marketSell0xOrdersFillOrKill` function to avoid the stack getting too deep.
     * @param lossRate The loss rate of the next hypothetical currency exchange (scaled by 1e18).
     * @return Boolean indicating success.
     */
    function checkLossRateLimit(int256 lossRate) internal view returns (bool) {
        int256 lossRateLastDay = 0;

        for (uint256 i = _lossRateHistory.length; i > 0; i--) {
            if (_lossRateHistory[i - 1].timestamp < block.timestamp.sub(86400)) break;
            lossRateLastDay = lossRateLastDay.add(_lossRateHistory[i - 1].lossRate);
        }

        return lossRateLastDay.add(lossRate) <= int256(_dailyLossRateLimit);
    }
}
