// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "@0x/contracts-exchange-libs/contracts/src/LibOrder.sol";

import "./RariFundController.sol";
import "./RariFundToken.sol";
import "./RariFundPriceConsumer.sol";
import "./interfaces/IRariGovernanceTokenDistributor.sol";

/**
 * @title RariFundManager
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice This contract is the primary contract powering the Rari Stable Pool.
 * Anyone can deposit to the fund with deposit(string currencyCode, uint256 amount).
 * Anyone can withdraw their funds (with interest) from the fund with withdraw(string currencyCode, uint256 amount).
 */
contract RariFundManager is Initializable, Ownable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeERC20 for IERC20;

    /**
     * @dev Boolean that, if true, disables the primary functionality of this RariFundManager.
     */
    bool public fundDisabled;

    /**
     * @dev Address of the RariFundController.
     */
    address payable private _rariFundControllerContract;

    /**
     * @dev Contract of the RariFundController.
     */
    RariFundController public rariFundController;

    /**
     * @dev Address of the RariFundToken.
     */
    address private _rariFundTokenContract;

    /**
     * @dev Contract of the RariFundToken.
     */
    RariFundToken public rariFundToken;

    /**
     * @dev Contract of the RariFundPriceConsumer.
     */
    RariFundPriceConsumer public rariFundPriceConsumer;

    /**
     * @dev Address of the RariFundProxy.
     */
    address private _rariFundProxyContract;

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
     * @dev UNUSED AFTER UPGRADE: Maps currency codes to arrays of supported pools.
     */
    mapping(string => RariFundController.LiquidityPool[]) private _poolsByCurrency;

    /**
     * @dev Initializer that sets supported ERC20 contract addresses and supported pools for each supported token.
     */
    function initialize() public initializer {
        // Initialize base contracts
        Ownable.initialize(msg.sender);
        
        // Add supported currencies
        addSupportedCurrency("DAI", 0x6B175474E89094C44Da98b954EedeAC495271d0F, 18);
        addSupportedCurrency("USDC", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 6);
        addSupportedCurrency("USDT", 0xdAC17F958D2ee523a2206206994597C13D831ec7, 6);
        addSupportedCurrency("TUSD", 0x0000000000085d4780B73119b644AE5ecd22b376, 18);
        addSupportedCurrency("BUSD", 0x4Fabb145d64652a948d72533023f6E7A623C7C53, 18);
        addSupportedCurrency("sUSD", 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51, 18);
        addSupportedCurrency("mUSD", 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5, 18);

        // Initialize raw fund balance cache (can't set initial values in field declarations with proxy storage)
        _rawFundBalanceCache = -1;
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
     * @dev Emitted when RariFundManager is upgraded.
     */
    event FundManagerUpgraded(address newContract);

    /**
     * @dev Upgrades RariFundManager.
     * Sends data to the new contract and sets the new RariFundToken minter.
     * @param newContract The address of the new RariFundManager contract.
     */
    function upgradeFundManager(address newContract) external onlyOwner {
        require(fundDisabled, "This fund manager contract must be disabled before it can be upgraded.");

        // Pass data to the new contract
        FundManagerData memory data;

        data = FundManagerData(
            _netDeposits,
            _rawInterestAccruedAtLastFeeRateChange,
            _interestFeesGeneratedAtLastFeeRateChange,
            _interestFeesClaimed
        );

        RariFundManager(newContract).setFundManagerData(data);

        // Update RariFundToken minter
        if (_rariFundTokenContract != address(0)) {
            rariFundToken.addMinter(newContract);
            rariFundToken.renounceMinter();
        }

        emit FundManagerUpgraded(newContract);
    }

    /**
     * @dev Old RariFundManager contract authorized to migrate its data to the new one.
     */
    address private _authorizedFundManagerDataSource;

    /**
     * @dev Upgrades RariFundManager.
     * Authorizes the source for fund manager data (i.e., the old fund manager).
     * @param authorizedFundManagerDataSource Authorized source for data (i.e., the old fund manager).
     */
    function authorizeFundManagerDataSource(address authorizedFundManagerDataSource) external onlyOwner {
        _authorizedFundManagerDataSource = authorizedFundManagerDataSource;
    }

    /**
     * @dev Struct for data to transfer from the old RariFundManager to the new one.
     */
    struct FundManagerData {
        int256 netDeposits;
        int256 rawInterestAccruedAtLastFeeRateChange;
        int256 interestFeesGeneratedAtLastFeeRateChange;
        uint256 interestFeesClaimed;
    }

    /**
     * @dev Upgrades RariFundManager.
     * Sets data receieved from the old contract.
     * @param data The data from the old contract necessary to initialize the new contract.
     */
    function setFundManagerData(FundManagerData calldata data) external {
        require(_authorizedFundManagerDataSource != address(0) && msg.sender == _authorizedFundManagerDataSource, "Caller is not an authorized source.");
        _netDeposits = data.netDeposits;
        _rawInterestAccruedAtLastFeeRateChange = data.rawInterestAccruedAtLastFeeRateChange;
        _interestFeesGeneratedAtLastFeeRateChange = data.interestFeesGeneratedAtLastFeeRateChange;
        _interestFeesClaimed = data.interestFeesClaimed;
        _interestFeeRate = RariFundManager(_authorizedFundManagerDataSource).getInterestFeeRate();
        _withdrawalFeeRate = RariFundManager(_authorizedFundManagerDataSource).getWithdrawalFeeRate();
    }

    /**
     * @dev Emitted when the RariFundController of the RariFundManager is set or upgraded.
     */
    event FundControllerSet(address newContract);

    /**
     * @dev Sets or upgrades the RariFundController of the RariFundManager.
     * @param newContract The address of the new RariFundController contract.
     */
    function setFundController(address payable newContract) external onlyOwner {
        _rariFundControllerContract = newContract;
        rariFundController = RariFundController(_rariFundControllerContract);
        emit FundControllerSet(newContract);
    }

    /**
     * @dev Forwards tokens lost in the fund manager (in case of accidental transfer of funds to this contract).
     * @param erc20Contract The ERC20 contract address of the token to forward.
     * @param to The destination address to which the funds will be forwarded.
     * @return Boolean indicating success.
     */
    function forwardLostFunds(address erc20Contract, address to) external onlyOwner returns (bool) {
        IERC20 token = IERC20(erc20Contract);
        uint256 balance = token.balanceOf(address(this));
        if (balance <= 0) return false;
        token.safeTransfer(to, balance);
        return true;
    }

    /**
     * @dev Emitted when the RariFundToken of the RariFundManager is set.
     */
    event FundTokenSet(address newContract);

    /**
     * @dev Sets or upgrades the RariFundToken of the RariFundManager.
     * @param newContract The address of the new RariFundToken contract.
     */
    function setFundToken(address newContract) external onlyOwner {
        _rariFundTokenContract = newContract;
        rariFundToken = RariFundToken(_rariFundTokenContract);
        emit FundTokenSet(newContract);
    }

    /**
     * @dev Emitted when the RariFundProxy of the RariFundManager is set.
     */
    event FundProxySet(address newContract);

    /**
     * @dev Sets or upgrades the RariFundProxy of the RariFundManager.
     * @param newContract The address of the new RariFundProxy contract.
     */
    function setFundProxy(address newContract) external onlyOwner {
        _rariFundProxyContract = newContract;
        emit FundProxySet(newContract);
    }

    /**
     * @dev Throws if called by any account other than the RariFundProxy.
     */
    modifier onlyProxy() {
        require(_rariFundProxyContract == msg.sender, "Caller is not the RariFundProxy.");
        _;
    }

    /**
     * @dev Emitted when the rebalancer of the RariFundManager is set.
     */
    event FundRebalancerSet(address newAddress);

    /**
     * @dev Sets or upgrades the rebalancer of the RariFundManager.
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
     * @dev Emitted when the RariFundPriceConsumer of the RariFundManager is set.
     */
    event FundPriceConsumerSet(address newContract);

    /**
     * @dev Sets or upgrades the RariFundPriceConsumer of the RariFundManager.
     * @param newContract The address of the new RariFundPriceConsumer contract.
     */
    function setFundPriceConsumer(address newContract) external onlyOwner {
        rariFundPriceConsumer = RariFundPriceConsumer(newContract);
        emit FundPriceConsumerSet(newContract);
    }

    /**
     * @dev Emitted when the primary functionality of this RariFundManager contract has been disabled.
     */
    event FundDisabled();

    /**
     * @dev Emitted when the primary functionality of this RariFundManager contract has been enabled.
     */
    event FundEnabled();

    /**
     * @dev Disables/enables primary functionality of this RariFundManager so contract(s) can be upgraded.
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
        require(!fundDisabled, "This fund manager contract is disabled. This may be due to an upgrade.");
        _;
    }

    /**
     * @dev Boolean indicating if return values of `getPoolBalance` are to be cached.
     */
    bool _cachePoolBalances;

    /**
     * @dev Boolean indicating if dYdX balances returned by `getPoolBalance` are to be cached.
     */
    bool _cacheDydxBalances;

    /**
     * @dev Maps to currency codes to cached pool balances to pool indexes.
     */
    mapping(string => mapping(uint8 => uint256)) _poolBalanceCache;

    /**
     * @dev Cached array of dYdX token addresses.
     */
    address[] private _dydxTokenAddressesCache;

    /**
     * @dev Cached array of dYdX balances.
     */
    uint256[] private _dydxBalancesCache;

    /**
     * @dev Returns the fund controller's balance of the specified currency in the specified pool.
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `CompoundPoolController.getBalance`) potentially modifies the state.
     * @param pool The index of the pool.
     * @param currencyCode The currency code of the token.
     */
    function getPoolBalance(uint8 pool, string memory currencyCode) internal returns (uint256) {
        if (!rariFundController.hasCurrencyInPool(pool, currencyCode)) return 0;

        if (_cachePoolBalances || _cacheDydxBalances) {
            if (pool == uint8(RariFundController.LiquidityPool.dYdX)) {
                address erc20Contract = _erc20Contracts[currencyCode];
                require(erc20Contract != address(0), "Invalid currency code.");
                if (_dydxBalancesCache.length == 0) (_dydxTokenAddressesCache, _dydxBalancesCache) = rariFundController.getDydxBalances();
                for (uint256 i = 0; i < _dydxBalancesCache.length; i++) if (_dydxTokenAddressesCache[i] == erc20Contract) return _dydxBalancesCache[i];
                revert("Failed to get dYdX balance of this currency code.");
            } else if (_cachePoolBalances) {
                if (_poolBalanceCache[currencyCode][pool] == 0) _poolBalanceCache[currencyCode][pool] = rariFundController._getPoolBalance(pool, currencyCode);
                return _poolBalanceCache[currencyCode][pool];
            }
        }

        return rariFundController._getPoolBalance(pool, currencyCode);
    }

    /**
     * @dev Caches dYdX pool balances returned by `getPoolBalance` for the duration of the function.
     */
    modifier cacheDydxBalances() {
        bool cacheSetPreviously = _cacheDydxBalances;
        _cacheDydxBalances = true;
        _;

        if (!cacheSetPreviously) {
            _cacheDydxBalances = false;
            if (!_cachePoolBalances) _dydxBalancesCache.length = 0;
        }
    }

    /**
     * @dev Caches return values of `getPoolBalance` for the duration of the function.
     */
    modifier cachePoolBalances() {
        bool cacheSetPreviously = _cachePoolBalances;
        _cachePoolBalances = true;
        _;

        if (!cacheSetPreviously) {
            _cachePoolBalances = false;
            if (!_cacheDydxBalances) _dydxBalancesCache.length = 0;

            for (uint256 i = 0; i < _supportedCurrencies.length; i++) {
                string memory currencyCode = _supportedCurrencies[i];
                uint8[] memory poolsByCurrency = rariFundController.getPoolsByCurrency(currencyCode);
                for (uint256 j = 0; j < poolsByCurrency.length; j++) _poolBalanceCache[currencyCode][uint8(poolsByCurrency[j])] = 0;
            }
        }
    }

    /**
     * @notice Returns the fund's raw total balance (all RFT holders' funds + all unclaimed fees) of the specified currency.
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `RariFundController.getPoolBalance`) potentially modifies the state.
     * @param currencyCode The currency code of the balance to be calculated.
     */
    function getRawFundBalance(string memory currencyCode) public returns (uint256) {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");

        IERC20 token = IERC20(erc20Contract);
        uint256 totalBalance = token.balanceOf(_rariFundControllerContract);
        uint8[] memory poolsByCurrency = rariFundController.getPoolsByCurrency(currencyCode);
        for (uint256 i = 0; i < poolsByCurrency.length; i++)
            totalBalance = totalBalance.add(getPoolBalance(poolsByCurrency[i], currencyCode));

        return totalBalance;
    }

    /**
     * @dev Caches the fund's raw total balance (all RFT holders' funds + all unclaimed fees) of all currencies in USD (scaled by 1e18).
     */
    int256 private _rawFundBalanceCache;

    /**
     * @notice Returns the fund's raw total balance (all RFT holders' funds + all unclaimed fees) of all currencies in USD (scaled by 1e18).
     * Returns `_rawFundBalanceCache` if set to save gas.
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `getRawFundBalance`) potentially modifies the state.
     */
    function getRawFundBalance() public returns (uint256) {
        if (_rawFundBalanceCache >= 0) return uint256(_rawFundBalanceCache);
        uint256[] memory pricesInUsd = rariFundPriceConsumer.getCurrencyPricesInUsd();
        return getRawFundBalance(pricesInUsd);
    }

    /**
     * @dev Returns the fund's raw total balance (all RFT holders' funds + all unclaimed fees) of all currencies in USD (scaled by 1e18).
     * Accepts prices in USD as a parameter to avoid calculating them every time.
     * Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `getRawFundBalance`) potentially modifies the state.
     */
    function getRawFundBalance(uint256[] memory pricesInUsd) public cacheDydxBalances returns (uint256) {
        uint256 totalBalance = 0;

        for (uint256 i = 0; i < _supportedCurrencies.length; i++) {
            string memory currencyCode = _supportedCurrencies[i];
            uint256 balance = getRawFundBalance(currencyCode);
            uint256 balanceUsd = balance.mul(pricesInUsd[i]).div(10 ** _currencyDecimals[currencyCode]);
            totalBalance = totalBalance.add(balanceUsd);
        }

        return totalBalance;
    }

    /**
     * @dev Caches the value of `getRawFundBalance()` for the duration of the function.
     */
    modifier cacheRawFundBalance() {
        bool cacheSetPreviously = _rawFundBalanceCache >= 0;
        if (!cacheSetPreviously) _rawFundBalanceCache = toInt256(getRawFundBalance());
        _;
        if (!cacheSetPreviously) _rawFundBalanceCache = -1;
    }

    /**
     * @notice Returns the fund's total investor balance (all RFT holders' funds but not unclaimed fees) of all currencies in USD (scaled by 1e18).
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `getRawFundBalance`) potentially modifies the state.
     */
    function getFundBalance() public cacheRawFundBalance returns (uint256) {
        return getRawFundBalance().sub(getInterestFeesUnclaimed());
    }

    /**
     * @notice Returns the total balance in USD (scaled by 1e18) of `account`.
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `getRawFundBalance`) potentially modifies the state.
     * @param account The account whose balance we are calculating.
     */
    function balanceOf(address account) external returns (uint256) {
        uint256 rftTotalSupply = rariFundToken.totalSupply();
        if (rftTotalSupply == 0) return 0;
        uint256 rftBalance = rariFundToken.balanceOf(account);
        uint256 fundBalanceUsd = getFundBalance();
        uint256 accountBalanceUsd = rftBalance.mul(fundBalanceUsd).div(rftTotalSupply);
        return accountBalanceUsd;
    }

    /**
     * @dev UNUSED AFTER UPGRADE: Fund balance limit in USD per Ethereum address.
     */
    uint256 private _accountBalanceLimitDefault;

    /**
     * @dev UNUSED AFTER UPGRADE: Maps user accounts to individual account balance limits (where 0 indicates the default while any negative value indicates 0).
     */
    mapping(address => int256) private _accountBalanceLimits;

    /**
     * @dev Maps currency codes to booleans indicating if they are accepted for deposits.
     */
    mapping(string => bool) private _acceptedCurrencies;

    /**
     * @notice Returns a boolean indicating if deposits in `currencyCode` are currently accepted.
     * @param currencyCode The currency code to check.
     */
    function isCurrencyAccepted(string memory currencyCode) public view returns (bool) {
        return _acceptedCurrencies[currencyCode];
    }

    /**
     * @dev UNUSED AFTER UPGRADE: Array of accepted currencies (only used by `getAcceptedCurrencies`).
     */
    string[] private _acceptedCurrenciesArray;

    /**
     * @notice Returns an array of currency codes currently accepted for deposits.
     */
    function getAcceptedCurrencies() external view returns (string[] memory) {
        uint256 arrayLength = 0;
        for (uint256 i = 0; i < _supportedCurrencies.length; i++) if (_acceptedCurrencies[_supportedCurrencies[i]]) arrayLength++;
        string[] memory acceptedCurrencies = new string[](arrayLength);
        uint256 index = 0;

        for (uint256 i = 0; i < _supportedCurrencies.length; i++) if (_acceptedCurrencies[_supportedCurrencies[i]]) {
            acceptedCurrencies[index] = _supportedCurrencies[i];
            index++;
        }

        return acceptedCurrencies;
    }

    /**
     * @dev Marks `currencyCodes` as accepted or not accepted.
     * @param currencyCodes The currency codes to mark as accepted or not accepted.
     * @param accepted An array of booleans indicating if each of `currencyCodes` is to be accepted.
     */
    function setAcceptedCurrencies(string[] calldata currencyCodes, bool[] calldata accepted) external onlyRebalancer {
        require (currencyCodes.length > 0 && currencyCodes.length == accepted.length, "Lengths of arrays must be equal and both greater than 0.");
        for (uint256 i = 0; i < currencyCodes.length; i++) _acceptedCurrencies[currencyCodes[i]] = accepted[i];
    }

    /**
     * @dev Emitted when funds have been deposited to RariFund.
     */
    event Deposit(string indexed currencyCode, address indexed sender, address indexed payee, uint256 amount, uint256 amountUsd, uint256 rftMinted);

    /**
     * @dev Emitted when funds have been withdrawn from RariFund.
     */
    event Withdrawal(string indexed currencyCode, address indexed sender, address indexed payee, uint256 amount, uint256 amountUsd, uint256 rftBurned, uint256 withdrawalFeeRate);

    /**
     * @notice Deposits funds from `msg.sender` to the Rari Stable Pool in exchange for RFT minted to `to`.
     * You may only deposit currencies accepted by the fund (see `isCurrencyAccepted(string currencyCode)`).
     * Please note that you must approve RariFundManager to transfer at least `amount`.
     * @param to The address that will receieve the minted RFT.
     * @param currencyCode The currency code of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     */
    function depositTo(address to, string memory currencyCode, uint256 amount) public fundEnabled {
        // Input validation
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        require(isCurrencyAccepted(currencyCode), "This currency is not currently accepted; please convert your funds to an accepted currency before depositing.");
        require(amount > 0, "Deposit amount must be greater than 0.");

        // Get currency prices
        uint256[] memory pricesInUsd = rariFundPriceConsumer.getCurrencyPricesInUsd();

        // Manually cache raw fund balance
        bool cacheSetPreviously = _rawFundBalanceCache >= 0;
        if (!cacheSetPreviously) _rawFundBalanceCache = toInt256(getRawFundBalance(pricesInUsd));

        // Get deposit amount in USD
        uint256 amountUsd = amount.mul(pricesInUsd[_currencyIndexes[currencyCode]]).div(10 ** _currencyDecimals[currencyCode]);

        // Calculate RFT to mint
        uint256 rftTotalSupply = rariFundToken.totalSupply();
        uint256 fundBalanceUsd = rftTotalSupply > 0 ? getFundBalance() : 0; // Only set if used
        uint256 rftAmount = 0;
        if (rftTotalSupply > 0 && fundBalanceUsd > 0) rftAmount = amountUsd.mul(rftTotalSupply).div(fundBalanceUsd);
        else rftAmount = amountUsd;
        require(rftAmount > 0, "Deposit amount is so small that no RFT would be minted.");

        // Update net deposits, transfer funds from msg.sender, mint RFT, and emit event
        _netDeposits = _netDeposits.add(int256(amountUsd));
        IERC20(erc20Contract).safeTransferFrom(msg.sender, _rariFundControllerContract, amount); // The user must approve the transfer of tokens beforehand
        require(rariFundToken.mint(to, rftAmount), "Failed to mint output tokens.");
        emit Deposit(currencyCode, msg.sender, to, amount, amountUsd, rftAmount);

        // Update _rawFundBalanceCache
        _rawFundBalanceCache = _rawFundBalanceCache.add(int256(amountUsd));

        // Update RGT distribution speeds
        IRariGovernanceTokenDistributor rariGovernanceTokenDistributor = rariFundToken.rariGovernanceTokenDistributor();
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number < rariGovernanceTokenDistributor.distributionEndBlock()) rariGovernanceTokenDistributor.refreshDistributionSpeeds(IRariGovernanceTokenDistributor.RariPool.Stable, getFundBalance());

        // Clear _rawFundBalanceCache
        if (!cacheSetPreviously) _rawFundBalanceCache = -1;
    }

    /**
     * @notice Deposits funds to the Rari Stable Pool in exchange for RFT.
     * You may only deposit currencies accepted by the fund (see `isCurrencyAccepted(string currencyCode)`).
     * Please note that you must approve RariFundManager to transfer at least `amount`.
     * @param currencyCode The currency code of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     */
    function deposit(string calldata currencyCode, uint256 amount) external {
        depositTo(msg.sender, currencyCode, amount);
    }

    /**
     * @dev Returns the amount of RFT to burn for a withdrawal (used by `_withdrawFrom`).
     * @param from The address from which RFT will be burned.
     * @param amountUsd The amount of the withdrawal in USD
     */
    function getRftBurnAmount(address from, uint256 amountUsd) internal returns (uint256) {
        uint256 rftTotalSupply = rariFundToken.totalSupply();
        uint256 fundBalanceUsd = getFundBalance();
        require(fundBalanceUsd > 0, "Fund balance is zero.");
        uint256 rftAmount = amountUsd.mul(rftTotalSupply).div(fundBalanceUsd);
        require(rftAmount <= rariFundToken.balanceOf(from), "Your RFT balance is too low for a withdrawal of this amount.");
        require(rftAmount > 0, "Withdrawal amount is so small that no RFT would be burned.");
        return rftAmount;
    }

    /**
     * @dev Internal function to withdraw funds from pools if necessary for `RariFundController` to hold at least `amount` of actual tokens.
     * This function was separated from `_withdrawFrom` to avoid the stack going too deep.
     * @param currencyCode The currency code of the token to be withdrawn.
     * @param amount The minimum amount of tokens that must be held by `RariFundController` after withdrawing.
     */
    function withdrawFromPoolsIfNecessary(string memory currencyCode, uint256 amount) internal {
        // Check contract balance of token
        address erc20Contract = _erc20Contracts[currencyCode];
        uint256 contractBalance = IERC20(erc20Contract).balanceOf(_rariFundControllerContract);

        // Withdraw from pools if necessary
        uint8[] memory poolsByCurrency = rariFundController.getPoolsByCurrency(currencyCode);

        for (uint256 i = 0; i < poolsByCurrency.length; i++) {
            if (contractBalance >= amount) break;
            uint8 pool = poolsByCurrency[i];
            uint256 poolBalance = getPoolBalance(pool, currencyCode);
            if (poolBalance <= 0) continue;
            uint256 amountLeft = amount.sub(contractBalance);
            bool withdrawAll = amountLeft >= poolBalance;
            uint256 poolAmount = withdrawAll ? poolBalance : amountLeft;
            rariFundController.withdrawFromPoolOptimized(pool, currencyCode, poolAmount, withdrawAll);

            if (pool == uint8(RariFundController.LiquidityPool.dYdX)) {
                for (uint256 j = 0; j < _dydxBalancesCache.length; j++) if (_dydxTokenAddressesCache[j] == erc20Contract) _dydxBalancesCache[j] = poolBalance.sub(poolAmount);
            } else _poolBalanceCache[currencyCode][pool] = poolBalance.sub(poolAmount);

            contractBalance = contractBalance.add(poolAmount);
        }

        // Final check of amount <= contractBalance
        require(amount <= contractBalance, "Available balance not enough to cover amount even after withdrawing from pools.");
    }

    /**
     * @dev Internal function to withdraw funds from the Rari Stable Pool to `msg.sender` in exchange for RFT burned from `from`.
     * You may only withdraw currencies held by the fund (see `getRawFundBalance(string currencyCode)`).
     * Please note that you must approve RariFundManager to burn of the necessary amount of RFT.
     * @param from The address from which RFT will be burned.
     * @param currencyCode The currency code of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     * @return The amount withdrawn after the fee.
     */
    function _withdrawFrom(address from, string memory currencyCode, uint256 amount, uint256[] memory pricesInUsd) internal fundEnabled cachePoolBalances returns (uint256) {
        // Input validation
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        require(amount > 0, "Withdrawal amount must be greater than 0.");

        // Withdraw from pools if necessary
        withdrawFromPoolsIfNecessary(currencyCode, amount);

        // Manually cache raw fund balance
        bool cacheSetPreviously = _rawFundBalanceCache >= 0;
        if (!cacheSetPreviously) _rawFundBalanceCache = toInt256(getRawFundBalance(pricesInUsd));

        // Calculate withdrawal fee and amount after fee
        uint256 feeAmount = amount.mul(_withdrawalFeeRate).div(1e18);
        uint256 amountAfterFee = amount.sub(feeAmount);

        // Get withdrawal amount in USD
        uint256 amountUsd = amount.mul(pricesInUsd[_currencyIndexes[currencyCode]]).div(10 ** _currencyDecimals[currencyCode]);

        // Calculate RFT to burn
        uint256 rftAmount = getRftBurnAmount(from, amountUsd);

        // Update net deposits, burn RFT, transfer funds to msg.sender, transfer fee to _withdrawalFeeMasterBeneficiary, and emit event
        _netDeposits = _netDeposits.sub(int256(amountUsd));
        rariFundToken.fundManagerBurnFrom(from, rftAmount); // The user must approve the burning of tokens beforehand
        IERC20 token = IERC20(erc20Contract);
        token.safeTransferFrom(_rariFundControllerContract, msg.sender, amountAfterFee);
        token.safeTransferFrom(_rariFundControllerContract, _withdrawalFeeMasterBeneficiary, feeAmount);
        emit Withdrawal(currencyCode, from, msg.sender, amount, amountUsd, rftAmount, _withdrawalFeeRate);

        // Update _rawFundBalanceCache
        _rawFundBalanceCache = _rawFundBalanceCache.sub(int256(amountUsd));

        // Update RGT distribution speeds
        IRariGovernanceTokenDistributor rariGovernanceTokenDistributor = rariFundToken.rariGovernanceTokenDistributor();
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number < rariGovernanceTokenDistributor.distributionEndBlock()) rariGovernanceTokenDistributor.refreshDistributionSpeeds(IRariGovernanceTokenDistributor.RariPool.Stable, getFundBalance());

        // Clear _rawFundBalanceCache
        if (!cacheSetPreviously) _rawFundBalanceCache = -1;

        // Return amount after fee
        return amountAfterFee;
    }

    /**
     * @notice Withdraws funds from the Rari Stable Pool in exchange for RFT.
     * You may only withdraw currencies held by the fund (see `getRawFundBalance(string currencyCode)`).
     * Please note that you must approve RariFundManager to burn of the necessary amount of RFT.
     * @param currencyCode The currency code of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     * @return The amount withdrawn after the fee.
     */
    function withdraw(string calldata currencyCode, uint256 amount) external returns (uint256) {
        return _withdrawFrom(msg.sender, currencyCode, amount, rariFundPriceConsumer.getCurrencyPricesInUsd());
    }

    /**
     * @dev Withdraws multiple currencies from the Rari Stable Pool to `msg.sender` (RariFundProxy) in exchange for RFT burned from `from`.
     * You may only withdraw currencies held by the fund (see `getRawFundBalance(string currencyCode)`).
     * Please note that you must approve RariFundManager to burn of the necessary amount of RFT.
     * @param from The address from which RFT will be burned.
     * @param currencyCodes The currency codes of the tokens to be withdrawn.
     * @param amounts The amounts of the tokens to be withdrawn.
     * @return Array of amounts withdrawn after fees.
     */
    // SWC-107-Reentrancy: L751 - L768
    function withdrawFrom(address from, string[] calldata currencyCodes, uint256[] calldata amounts) external onlyProxy cachePoolBalances returns (uint256[] memory) {
        // Input validation
        require(currencyCodes.length > 0 && currencyCodes.length == amounts.length, "Lengths of currency code and amount arrays must be greater than 0 and equal.");
        uint256[] memory pricesInUsd = rariFundPriceConsumer.getCurrencyPricesInUsd();

        // Manually cache raw fund balance (no need to check if set previously because the function is external)
        _rawFundBalanceCache = toInt256(getRawFundBalance(pricesInUsd));

        // Make withdrawals
        uint256[] memory amountsAfterFees = new uint256[](currencyCodes.length);
        for (uint256 i = 0; i < currencyCodes.length; i++) amountsAfterFees[i] = _withdrawFrom(from, currencyCodes[i], amounts[i], pricesInUsd);

        // Reset _rawFundBalanceCache
        _rawFundBalanceCache = -1;

        // Return amounts withdrawn after fees
        return amountsAfterFees;
    }

    /**
     * @dev Net quantity of deposits to the fund (i.e., deposits - withdrawals).
     * On deposit, amount deposited is added to `_netDeposits`; on withdrawal, amount withdrawn is subtracted from `_netDeposits`.
     */
    int256 private _netDeposits;

    /**
     * @notice Returns the raw total amount of interest accrued by the fund as a whole (including the fees paid on interest) in USD (scaled by 1e18).
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `getRawFundBalance`) potentially modifies the state.
     */
    function getRawInterestAccrued() public returns (int256) {
        return toInt256(getRawFundBalance()).sub(_netDeposits).add(toInt256(_interestFeesClaimed));
    }

    /**
     * @notice Returns the total amount of interest accrued by past and current RFT holders (excluding the fees paid on interest) in USD (scaled by 1e18).
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `getRawFundBalance`) potentially modifies the state.
     */
    function getInterestAccrued() public returns (int256) {
        return toInt256(getFundBalance()).sub(_netDeposits);
    }

    /**
     * @dev The proportion of interest accrued that is taken as a service fee (scaled by 1e18).
     */
    uint256 private _interestFeeRate;

    /**
     * @dev Returns the fee rate on interest (proportion of raw interest accrued scaled by 1e18).
     */
    function getInterestFeeRate() public view returns (uint256) {
        return _interestFeeRate;
    }

    /**
     * @dev Sets the fee rate on interest.
     * @param rate The proportion of interest accrued to be taken as a service fee (scaled by 1e18).
     */
    function setInterestFeeRate(uint256 rate) external fundEnabled onlyOwner cacheRawFundBalance {
        require(rate != _interestFeeRate, "This is already the current interest fee rate.");
        require(rate <= 1e18, "The interest fee rate cannot be greater than 100%.");
        _depositFees();
        _interestFeesGeneratedAtLastFeeRateChange = getInterestFeesGenerated(); // MUST update this first before updating _rawInterestAccruedAtLastFeeRateChange since it depends on it 
        _rawInterestAccruedAtLastFeeRateChange = getRawInterestAccrued();
        _interestFeeRate = rate;
    }

    /**
     * @dev The amount of interest accrued at the time of the most recent change to the fee rate.
     */
    int256 private _rawInterestAccruedAtLastFeeRateChange;

    /**
     * @dev The amount of fees generated on interest at the time of the most recent change to the fee rate.
     */
    int256 private _interestFeesGeneratedAtLastFeeRateChange;

    /**
     * @notice Returns the amount of interest fees accrued by beneficiaries in USD (scaled by 1e18).
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `getRawFundBalance`) potentially modifies the state.
     */
    function getInterestFeesGenerated() public returns (int256) {
        int256 rawInterestAccruedSinceLastFeeRateChange = getRawInterestAccrued().sub(_rawInterestAccruedAtLastFeeRateChange);
        int256 interestFeesGeneratedSinceLastFeeRateChange = rawInterestAccruedSinceLastFeeRateChange.mul(int256(_interestFeeRate)).div(1e18);
        int256 interestFeesGenerated = _interestFeesGeneratedAtLastFeeRateChange.add(interestFeesGeneratedSinceLastFeeRateChange);
        return interestFeesGenerated;
    }

    /**
     * @dev The total claimed amount of interest fees.
     */
    uint256 private _interestFeesClaimed;

    /**
     * @dev Returns the total unclaimed amount of interest fees.
     * Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `getRawFundBalance`) potentially modifies the state.
     */
    function getInterestFeesUnclaimed() public returns (uint256) {
        int256 interestFeesUnclaimed = getInterestFeesGenerated().sub(toInt256(_interestFeesClaimed));
        return interestFeesUnclaimed > 0 ? uint256(interestFeesUnclaimed) : 0;
    }

    /**
     * @dev The master beneficiary of fees on interest; i.e., the recipient of all fees on interest.
     */
    address private _interestFeeMasterBeneficiary;

    /**
     * @dev Sets the master beneficiary of interest fees.
     * @param beneficiary The master beneficiary of fees on interest; i.e., the recipient of all fees on interest.
     */
    function setInterestFeeMasterBeneficiary(address beneficiary) external fundEnabled onlyOwner {
        require(beneficiary != address(0), "Master beneficiary cannot be the zero address.");
        _interestFeeMasterBeneficiary = beneficiary;
    }

    /**
     * @dev Emitted when fees on interest are deposited back into the fund.
     */
    event InterestFeeDeposit(address beneficiary, uint256 amountUsd);

    /**
     * @dev Internal function to deposit all accrued fees on interest back into the fund on behalf of the master beneficiary.
     * @return Integer indicating success (0), no fees to claim (1), or no RFT to mint (2).
     */
    function _depositFees() internal fundEnabled cacheRawFundBalance returns (uint8) {
        // Input validation
        require(_interestFeeMasterBeneficiary != address(0), "Master beneficiary cannot be the zero address.");

        // Get and validate unclaimed interest fees
        uint256 amountUsd = getInterestFeesUnclaimed();
        if (amountUsd <= 0) return 1;

        // Calculate RFT amount to mint and validate
        uint256 rftTotalSupply = rariFundToken.totalSupply();
        uint256 rftAmount = 0;

        if (rftTotalSupply > 0) {
            uint256 fundBalanceUsd = getFundBalance();
            if (fundBalanceUsd > 0) rftAmount = amountUsd.mul(rftTotalSupply).div(fundBalanceUsd);
            else rftAmount = amountUsd;
        } else rftAmount = amountUsd;

        if (rftAmount <= 0) return 2;

        // Update claimed interest fees and net deposits, mint RFT, emit events, and return no error
        _interestFeesClaimed = _interestFeesClaimed.add(amountUsd);
        _netDeposits = _netDeposits.add(int256(amountUsd));
        require(rariFundToken.mint(_interestFeeMasterBeneficiary, rftAmount), "Failed to mint output tokens.");
        emit Deposit("USD", _interestFeeMasterBeneficiary, _interestFeeMasterBeneficiary, amountUsd, amountUsd, rftAmount);
        emit InterestFeeDeposit(_interestFeeMasterBeneficiary, amountUsd);

        // Update RGT distribution speeds
        IRariGovernanceTokenDistributor rariGovernanceTokenDistributor = rariFundToken.rariGovernanceTokenDistributor();
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number < rariGovernanceTokenDistributor.distributionEndBlock()) rariGovernanceTokenDistributor.refreshDistributionSpeeds(IRariGovernanceTokenDistributor.RariPool.Stable, getFundBalance());

        // Return no error
        return 0;
    }

    /**
     * @notice Deposits all accrued fees on interest back into the fund on behalf of the master beneficiary.
     * @return Boolean indicating success.
     */
    function depositFees() external onlyRebalancer {
        uint8 result = _depositFees();
        require(result == 0, result == 2 ? "Deposit amount is so small that no RFT would be minted." : "No new fees are available to claim.");
    }

    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     * @param value The uint256 to convert.
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        require(value < 2 ** 255, "SafeCast: value doesn't fit in an int256");
        return int256(value);
    }

    /**
     * @dev The current withdrawal fee rate (scaled by 1e18).
     */
    uint256 private _withdrawalFeeRate;

    /**
     * @dev The master beneficiary of withdrawal fees; i.e., the recipient of all withdrawal fees.
     */
    address private _withdrawalFeeMasterBeneficiary;

    /**
     * @dev Returns the withdrawal fee rate (proportion of every withdrawal taken as a service fee scaled by 1e18).
     */
    function getWithdrawalFeeRate() public view returns (uint256) {
        return _withdrawalFeeRate;
    }

    /**
     * @dev Sets the withdrawal fee rate.
     * @param rate The proportion of every withdrawal taken as a service fee (scaled by 1e18).
     */
    function setWithdrawalFeeRate(uint256 rate) external fundEnabled onlyOwner {
        require(rate != _withdrawalFeeRate, "This is already the current withdrawal fee rate.");
        require(rate <= 1e18, "The withdrawal fee rate cannot be greater than 100%.");
        _withdrawalFeeRate = rate;
    }

    /**
     * @dev Sets the master beneficiary of withdrawal fees.
     * @param beneficiary The master beneficiary of withdrawal fees; i.e., the recipient of all withdrawal fees.
     */
    function setWithdrawalFeeMasterBeneficiary(address beneficiary) external fundEnabled onlyOwner {
        require(beneficiary != address(0), "Master beneficiary cannot be the zero address.");
        _withdrawalFeeMasterBeneficiary = beneficiary;
    }
}
