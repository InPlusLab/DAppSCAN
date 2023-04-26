// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Detailed.sol";

import "@0x/contracts-exchange-libs/contracts/src/LibOrder.sol";

import "./RariFundManager.sol";
import "./lib/pools/DydxPoolController.sol";
import "./lib/pools/CompoundPoolController.sol";
import "./lib/pools/AavePoolController.sol";
import "./lib/pools/MStablePoolController.sol";
import "./lib/pools/FusePoolController.sol";
import "./lib/exchanges/MStableExchangeController.sol";
import "./lib/exchanges/UniswapExchangeController.sol";

import "./external/compound/CErc20.sol";

/**
 * @title RariFundController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice This contract handles deposits to and withdrawals from the liquidity pools that power the Rari Stable Pool as well as currency exchanges via 0x.
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
    bool private _fundDisabled;

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
    mapping(string => uint8) public _currencyIndexes;

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
    enum LiquidityPool { dYdX, Compound, Aave, mStable }

    /**
     * @dev Maps currency codes to arrays of supported pools.
     */
    mapping(string => uint8[]) private _poolsByCurrency;

    /**
     * @dev Constructor that sets supported ERC20 contract addresses and supported pools for each supported token.
     */
    function initialize() public initializer {
        // Initialize base contracts
        Ownable.initialize(msg.sender);
        
        // Add supported currencies
        addSupportedCurrency("DAI", 0x6B175474E89094C44Da98b954EedeAC495271d0F, 18);
        addPoolToCurrency("DAI", LiquidityPool.dYdX);
        addPoolToCurrency("DAI", LiquidityPool.Compound);
        addPoolToCurrency("DAI", LiquidityPool.Aave);
        addSupportedCurrency("USDC", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 6);
        addPoolToCurrency("USDC", LiquidityPool.dYdX);
        addPoolToCurrency("USDC", LiquidityPool.Compound);
        addPoolToCurrency("USDC", LiquidityPool.Aave);
        addSupportedCurrency("USDT", 0xdAC17F958D2ee523a2206206994597C13D831ec7, 6);
        addPoolToCurrency("USDT", LiquidityPool.Compound);
        addPoolToCurrency("USDT", LiquidityPool.Aave);
        addSupportedCurrency("TUSD", 0x0000000000085d4780B73119b644AE5ecd22b376, 18);
        addPoolToCurrency("TUSD", LiquidityPool.Aave);
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
        _poolsByCurrency[currencyCode].push(uint8(pool));
    }

    /**
     * @dev Sets or upgrades RariFundController by withdrawing all tokens from all pools and forwarding them from the old to the new.
     * @param newContract The address of the new RariFundController contract.
     */
    function upgradeFundController(address payable newContract) external onlyOwner {
        // Verify fund is disabled + verify new fund controller contract
        require(_fundDisabled, "This fund controller contract must be disabled before it can be upgraded.");
        require(RariFundController(newContract).IS_RARI_FUND_CONTROLLER(), "New contract does not have IS_RARI_FUND_CONTROLLER set to true.");

        // For each supported currency:
    //  SWC-DoS With Block Gas Limit: L52
        for (uint256 i = 0; i < _supportedCurrencies.length; i++) {
            string memory currencyCode = _supportedCurrencies[i];

            // For each pool supported by this currency:
            for (uint256 j = 0; j < _poolsByCurrency[currencyCode].length; j++) {
                uint8 pool = _poolsByCurrency[currencyCode][j];

                // If the pool has any funds in this currency, withdraw it
                if (hasCurrencyInPool(pool, currencyCode)) {           
                    if (fuseAssets[pool][currencyCode] != address(0)) FusePoolController.transferAll(fuseAssets[pool][currencyCode], newContract); // Transfer Fuse cTokens directly
                    else _withdrawAllFromPool(pool, currencyCode);
                }
            }

            // Transfer all of this token to new fund controller
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
        // Verify fund is disabled + verify new fund controller contract
        require(_fundDisabled, "This fund controller contract must be disabled before it can be upgraded.");
        require(RariFundController(newContract).IS_RARI_FUND_CONTROLLER(), "New contract does not have IS_RARI_FUND_CONTROLLER set to true.");

        // Transfer all of this token to new fund controller
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
     * @dev Returns `_poolsByCurrency[currencyCode]`. Used by `RariFundManager` and `RariFundProxy.getRawFundBalancesAndPrices`.
     */
    function getPoolsByCurrency(string calldata currencyCode) external view returns (uint8[] memory) {
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
    function _getPoolBalance(uint8 pool, string memory currencyCode) public returns (uint256) {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == uint8(LiquidityPool.dYdX)) return DydxPoolController.getBalance(erc20Contract);
        else if (pool == uint8(LiquidityPool.Compound)) return CompoundPoolController.getBalance(erc20Contract);
        else if (pool == uint8(LiquidityPool.Aave)) return AavePoolController.getBalance(erc20Contract);
        else if (pool == uint8(LiquidityPool.mStable) && erc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) return MStablePoolController.getBalance();
        else if (fuseAssets[pool][currencyCode] != address(0)) return FusePoolController.getBalance(fuseAssets[pool][currencyCode]);
        else revert("Invalid pool index.");
    }

    /**
     * @dev Returns the fund controller's balance of the specified currency in the specified pool (checking `_poolsWithFunds` first to save gas).
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `CompoundPoolController.getBalance`) potentially modifies the state.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token.
     */
    function getPoolBalance(uint8 pool, string memory currencyCode) public returns (uint256) {
        if (!_poolsWithFunds[currencyCode][pool]) return 0;
        return _getPoolBalance(pool, currencyCode);
    }

    /**
     * @dev Approves tokens to the specified pool without spending gas on every deposit.
     * Note that this function is vulnerable to the allowance double-spend exploit, as with the `approve` functions of the ERC20 contracts themselves. If you are concerned and setting exact allowances, make sure to set allowance to 0 on the client side before setting an allowance greater than 0.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be approved.
     * @param amount The amount of tokens to be approved.
     */
    function approveToPool(uint8 pool, string calldata currencyCode, uint256 amount) external fundEnabled onlyRebalancer {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == uint8(LiquidityPool.dYdX)) DydxPoolController.approve(erc20Contract, amount);
        else if (pool == uint8(LiquidityPool.Compound)) CompoundPoolController.approve(erc20Contract, amount);
        else if (pool == uint8(LiquidityPool.Aave)) AavePoolController.approve(erc20Contract, amount);
        else if (pool == uint8(LiquidityPool.mStable) && erc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) return MStablePoolController.approve(amount);
        else if (fuseAssets[pool][currencyCode] != address(0)) FusePoolController.approve(fuseAssets[pool][currencyCode], erc20Contract, amount);
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
    event PoolAllocation(PoolAllocationAction indexed action, uint8 indexed pool, string indexed currencyCode, uint256 amount);

    /**
     * @dev Deposits funds to the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     */
    function depositToPool(uint8 pool, string calldata currencyCode, uint256 amount) external fundEnabled onlyRebalancer {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == uint8(LiquidityPool.dYdX)) DydxPoolController.deposit(erc20Contract, amount);
        else if (pool == uint8(LiquidityPool.Compound)) CompoundPoolController.deposit(erc20Contract, amount);
        else if (pool == uint8(LiquidityPool.Aave)) AavePoolController.deposit(erc20Contract, amount, _aaveReferralCode);
        else if (pool == uint8(LiquidityPool.mStable) && erc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) MStablePoolController.deposit(amount);
        else if (fuseAssets[pool][currencyCode] != address(0)) FusePoolController.deposit(fuseAssets[pool][currencyCode], amount);
        else revert("Invalid pool index.");
        _poolsWithFunds[currencyCode][pool] = true;
        emit PoolAllocation(PoolAllocationAction.Deposit, pool, currencyCode, amount);
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
        if (pool == uint8(LiquidityPool.dYdX)) DydxPoolController.withdraw(erc20Contract, amount);
        else if (pool == uint8(LiquidityPool.Compound)) CompoundPoolController.withdraw(erc20Contract, amount);
        else if (pool == uint8(LiquidityPool.Aave)) AavePoolController.withdraw(erc20Contract, amount);
        else if (pool == uint8(LiquidityPool.mStable) && erc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) MStablePoolController.withdraw(amount);
        else if (fuseAssets[pool][currencyCode] != address(0)) FusePoolController.withdraw(fuseAssets[pool][currencyCode], amount);
        else revert("Invalid pool index.");
        emit PoolAllocation(PoolAllocationAction.Withdraw, pool, currencyCode, amount);
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
     * @dev Withdraws funds from the specified pool (with optimizations based on the `all` parameter).
     * If we already know all funds are being withdrawn, we won't have to check again here in this function. 
     * If withdrawing all funds, we choose _withdrawFromPool or _withdrawAllFromPool based on estimated gas usage.
     * The value of `all` is trusted because `msg.sender` is always RariFundManager.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     * @param all Boolean indicating if all funds are being withdrawn.
     */
    function withdrawFromPoolOptimized(uint8 pool, string calldata currencyCode, uint256 amount, bool all) external fundEnabled onlyManager {
        all ? _withdrawAllFromPool(pool, currencyCode) : _withdrawFromPool(pool, currencyCode, amount);
        if (all) _poolsWithFunds[currencyCode][pool] = false;
    }

    /**
     * @dev Internal function to withdraw all funds from the specified pool.
     * @param pool The index of the pool.
     * @param currencyCode The ERC20 contract of the token to be withdrawn.
     */
    function _withdrawAllFromPool(uint8 pool, string memory currencyCode) internal {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        if (pool == uint8(LiquidityPool.dYdX)) DydxPoolController.withdrawAll(erc20Contract);
        else if (pool == uint8(LiquidityPool.Compound)) require(CompoundPoolController.withdrawAll(erc20Contract), "No Compound balance to withdraw from.");
        else if (pool == uint8(LiquidityPool.Aave)) require(AavePoolController.withdrawAll(erc20Contract), "No Aave balance to withdraw from.");
        else if (pool == uint8(LiquidityPool.mStable) && erc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) require(MStablePoolController.withdrawAll(), "No mStable balance to withdraw from.");
        else if (fuseAssets[pool][currencyCode] != address(0)) require(FusePoolController.withdrawAll(fuseAssets[pool][currencyCode]), "No Fuse pool balance to withdraw from.");
        else revert("Invalid pool index.");
        _poolsWithFunds[currencyCode][pool] = false;
        emit PoolAllocation(PoolAllocationAction.WithdrawAll, pool, currencyCode, 0);
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
     * @dev Enum for currency exchanges supported by Rari.
     */
    enum CurrencyExchange {
        ZeroEx, // No longer in use (kept to keep this enum backwards-compatible)
        mStable,
        Uniswap
    }

    /**
     * @dev Emitted when currencies are exchanged via 0x or mStable.
     * Note that `inputAmountUsd` and `outputAmountUsd` are not present when the input currency is not a supported stablecoin (i.e., when exchanging COMP via 0x).
     */
    event CurrencyTrade(string indexed inputCurrencyCode, string indexed outputCurrencyCode, uint256 inputAmount, uint256 inputAmountUsd, uint256 outputAmount, uint256 outputAmountUsd, CurrencyExchange indexed exchange);

    /**
     * @dev Per-trade and daily limit on exchange order slippage (scaled by 1e18) of supported stablecoins.
     */
    int256 private _exchangeLossRateLimit;

    /**
     * @dev Sets or upgrades the per-trade and daily limit on exchange order loss over raw total fund balance.
     * @param limit The per-trade and daily limit on exchange order loss over raw total fund balance (scaled by 1e18).
     */
    function setExchangeLossRateLimit(int256 limit) external onlyOwner {
        _exchangeLossRateLimit = limit;
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
     * @dev Gets currency code for `erc20Contract` if it maps to a valid supported currency code.
     */
    function getCurrencyCodeByErc20Contract(address erc20Contract) internal view returns (string memory) {
        for (uint256 i = 0; i < _supportedCurrencies.length; i++) if (_erc20Contracts[_supportedCurrencies[i]] == erc20Contract) return _supportedCurrencies[i];
        return "";
    }

    /**
     * @dev Market sell `inputAmount` via Uniswap (reverting if the output is not a supported stablecoin, there is not enough liquidity to sell `inputAmount`, `minOutputAmount` is not satisfied, or the 24-hour slippage limit is surpassed).
     * We should be able to make this function external and use calldata for all parameters, but Solidity does not support calldata structs (https://github.com/ethereum/solidity/issues/5479).
     * @param path The Uniswap V2 ERC20 token address path to use for the exchange.
     * @param inputAmount The amount of the input asset to sell/send.
     * @param minOutputAmount The minimum amount of the output asset to buy/receive.
     */
    function swapExactTokensForTokens(address[] calldata path, uint256 inputAmount, uint256 minOutputAmount) external fundEnabled onlyRebalancer {
        // Exchanges not supported if _exchangeLossRateLimit == min value for int256
        require(_exchangeLossRateLimit > int256(uint256(1) << 255), "Exchanges have been disabled.");

        // Check if input is a supported stablecoin and make sure output is a supported stablecoin
        string memory inputCurrencyCode = getCurrencyCodeByErc20Contract(path[0]);
        string memory outputCurrencyCode = getCurrencyCodeByErc20Contract(path[path.length - 1]);
        require(bytes(outputCurrencyCode).length > 0, "Output token is not a supported stablecoin.");

        // Get prices and raw fund balance before exchange
        uint256[] memory pricesInUsd;
        uint256 rawFundBalanceBeforeExchange;

        if (bytes(inputCurrencyCode).length > 0) {
            pricesInUsd = rariFundManager.rariFundPriceConsumer().getCurrencyPricesInUsd();
            rawFundBalanceBeforeExchange = rariFundManager.getRawFundBalance(pricesInUsd);
        }

        // Approve tokens
        UniswapExchangeController.approve(path[0], inputAmount);

        // Market sell
        uint256 outputAmount = UniswapExchangeController.swapExactTokensForTokens(inputAmount, minOutputAmount, path);

        // Check per-trade and 24-hour loss rate limit (if inputting a supported stablecoin)
        uint256 inputAmountUsd = 0;
        uint256 outputAmountUsd = 0;

        if (bytes(inputCurrencyCode).length > 0) {
            // Get amount in USD
            inputAmountUsd = toUsd(inputCurrencyCode, inputAmount, pricesInUsd);
            outputAmountUsd = toUsd(outputCurrencyCode, outputAmount, pricesInUsd);

            // Check loss rate limits
            handleExchangeLoss(inputAmountUsd, outputAmountUsd, rawFundBalanceBeforeExchange);
        }

        // Emit event
        emit CurrencyTrade(bytes(inputCurrencyCode).length > 0 ? inputCurrencyCode : ERC20Detailed(path[path.length - 1]).symbol(), outputCurrencyCode, inputAmount, inputAmountUsd, outputAmount, outputAmountUsd, CurrencyExchange.Uniswap);
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
        // Calculate loss in USD
        int256 lossUsd = int256(inputAmountUsd).sub(int256(outputAmountUsd));

        // Check per-trade loss rate limit (equals daily loss rate limit)
        int256 tradeLossRateOnTrade = lossUsd.mul(1e18).div(int256(inputAmountUsd));
        require(tradeLossRateOnTrade <= _exchangeLossRateLimit, "This exchange would violate the per-trade loss rate limit.");
        
        // Check if sum of loss rates over the last 24 hours + this trade's loss rate > the limit
        int256 lossRateLastDay = 0;

        for (uint256 i = _lossRateHistory.length; i > 0; i--) {
            // SWC-Block values as a proxy for time: L605
            if (_lossRateHistory[i - 1].timestamp < block.timestamp.sub(86400)) break;
            lossRateLastDay = lossRateLastDay.add(_lossRateHistory[i - 1].lossRate);
        }

        int256 tradeLossRateOnFund = lossUsd.mul(1e18).div(int256(rawFundBalanceBeforeExchange));
        require(lossRateLastDay.add(tradeLossRateOnFund) <= _exchangeLossRateLimit, "This exchange would violate the 24-hour loss rate limit.");

        // Log loss rate in history
        _lossRateHistory.push(CurrencyExchangeLoss(block.timestamp, tradeLossRateOnFund));
    }

    /**
     * @dev Swaps tokens via mStable mUSD.
     * @param inputCurrencyCode The currency code of the input token to be sold.
     * @param outputCurrencyCode The currency code of the output token to be bought.
     * @param inputAmount The amount of input tokens to be sold.
     * @param minOutputAmount The minimum amount of output tokens to be bought.
     */
    function swapMStable(string calldata inputCurrencyCode, string calldata outputCurrencyCode, uint256 inputAmount, uint256 minOutputAmount) external fundEnabled onlyRebalancer {
        // Exchanges not supported if _exchangeLossRateLimit == min value for int256
        require(_exchangeLossRateLimit > int256(uint256(1) << 255), "Exchanges have been disabled.");

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

        // Approve to mUSD
        MStableExchangeController.approve(inputErc20Contract, inputAmount);

        // Swap stablecoins via mUSD
        uint256 outputAmount = MStableExchangeController.swap(inputErc20Contract, outputErc20Contract, inputAmount, minOutputAmount);

        // Check 24-hour loss rate limit
        uint256 inputFilledAmountUsd = toUsd(inputCurrencyCode, inputAmount, pricesInUsd);
        uint256 outputFilledAmountUsd = toUsd(outputCurrencyCode, outputAmount, pricesInUsd);
        handleExchangeLoss(inputFilledAmountUsd, outputFilledAmountUsd, rawFundBalanceBeforeExchange);

        // Emit event
        emit CurrencyTrade(inputCurrencyCode, outputCurrencyCode, inputAmount, inputFilledAmountUsd, outputAmount, outputFilledAmountUsd, CurrencyExchange.mStable);
    }

    /**
     * @dev Claims mStable MTA rewards (if `all` is set, unlocks and claims locked rewards).
     * @param all If locked rewards should be unlocked and claimed.
     * @param first Index of the first array element to claim. Only applicable if `all` is true. Feed in the second value returned by the savings vault's `unclaimedRewards(address _account)` function.
     * @param last Index of the last array element to claim. Only applicable if `all` is true. Feed in the third value returned by the savings vault's `unclaimedRewards(address _account)` function.
     */
    function claimMStableRewards(bool all, uint256 first, uint256 last) external fundEnabled onlyRebalancer {
        MStablePoolController.claimRewards(all, first, last);
    }

    /**
     * @notice Fuse cToken contract addresses approved for deposits by the rebalancer.
     */
    mapping(uint8 => mapping(string => address)) public fuseAssets;

    /**
     * @dev Adds `cTokens` to `fuseAssets` (indexed by `pools` and `currencyCodes`).
     * @param pools The pool indexes.
     * @param currencyCodes The corresponding currency codes for `_fuseAssets`.
     * @param cTokens The Fuse cToken contract addresses.
     */
    function addFuseAssets(uint8[] calldata pools, string[][] calldata currencyCodes, address[][] calldata cTokens) external onlyOwner {
        require(pools.length > 0 && pools.length == currencyCodes.length && pools.length == cTokens.length, "Array parameter lengths must all be equal and greater than 0.");

        for (uint256 i = 0; i < pools.length; i++) {
            uint8 pool = pools[i];
            require(pool >= 100, "Pool index too low.");
            require(currencyCodes[i].length > 0 && currencyCodes[i].length == cTokens[i].length, "Nested array parameter lengths must all be equal and greater than 0.");

            for (uint256 j = 0; j < currencyCodes[i].length; j++) {
                address cToken = cTokens[i][j];
                string memory currencyCode = currencyCodes[i][j];
                require(fuseAssets[pool][currencyCode] == address(0), "cToken address already set for this currency code.");
                require(CErc20(cToken).underlying() == _erc20Contracts[currencyCode], "Underlying ERC20 token mismatch.");
                fuseAssets[pool][currencyCode] = cToken;
                _poolsByCurrency[currencyCode].push(pool);
            }
        }
    }
}
