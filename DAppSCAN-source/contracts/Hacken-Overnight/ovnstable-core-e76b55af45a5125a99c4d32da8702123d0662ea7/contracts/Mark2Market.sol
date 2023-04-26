// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/IMark2Market.sol";
import "./interfaces/IPriceGetter.sol";
import "./registries/Portfolio.sol";
import "./Vault.sol";

contract Mark2Market is IMark2Market, Initializable, AccessControlUpgradeable, UUPSUpgradeable{
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");


    // ---  fields

    Vault public vault;
    Portfolio public portfolio;

    // ---  events

    event VaultUpdated(address vault);
    event PortfolioUpdated(address portfolio);


    // ---  modifiers

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to admins");
        _;
    }


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(UPGRADER_ROLE)
    override
    {}


    // ---  setters

    function setVault(address _vault) external onlyAdmin {
        require(_vault != address(0), "Zero address not allowed");
        vault = Vault(_vault);
        emit VaultUpdated(_vault);
    }

    function setPortfolio(address _portfolio) external onlyAdmin {
        require(_portfolio != address(0), "Zero address not allowed");
        portfolio = Portfolio(_portfolio);
        emit PortfolioUpdated(_portfolio);
    }

    // ---  logic


    function assetPricesView() public view returns(AssetPrices[] memory){
        return assetPrices().assetPrices;
    }

    function assetPrices() public view override returns (TotalAssetPrices memory) {
        Portfolio.AssetInfo[] memory assetInfos = portfolio.getAllAssetInfos();

        uint256 totalUsdcPrice = 0;
        uint256 count = assetInfos.length;
        AssetPrices[] memory assetPrices = new AssetPrices[](count);
        for (uint8 i = 0; i < count; i++) {
            Portfolio.AssetInfo memory assetInfo = assetInfos[i];
            uint256 amountInVault = _currentAmountInVault(assetInfo.asset);

            IPriceGetter priceGetter = IPriceGetter(assetInfo.priceGetter);

            uint256 usdcPriceDenominator = priceGetter.denominator();
            uint256 usdcSellPrice = priceGetter.getUsdcSellPrice();
            uint256 usdcBuyPrice = priceGetter.getUsdcBuyPrice();

            // in decimals: 18 + 18 - 18 => 18
            uint256 usdcPriceInVault = (amountInVault * usdcSellPrice) / usdcPriceDenominator;

            totalUsdcPrice += usdcPriceInVault;

            assetPrices[i] = AssetPrices(
                assetInfo.asset,
                amountInVault,
                usdcPriceInVault,
                usdcPriceDenominator,
                usdcSellPrice,
                usdcBuyPrice,
                IERC20Metadata(assetInfo.asset).decimals(),
                IERC20Metadata(assetInfo.asset).name(),
                IERC20Metadata(assetInfo.asset).symbol()
            );
        }

        TotalAssetPrices memory totalPrices = TotalAssetPrices(assetPrices, totalUsdcPrice);

        return totalPrices;
    }


    function totalSellAssets() public view override returns(uint256){
        return totalAssets(true);
    }

    function totalBuyAssets() public view override returns(uint256){
        return totalAssets(false);
    }

    function totalAssets(bool sell) internal view returns (uint256)
    {
        Portfolio.AssetWeight[] memory assetWeights = portfolio.getAllAssetWeights();

        uint256 totalUsdcPrice = 0;
        uint256 count = assetWeights.length;
        for (uint8 i = 0; i < count; i++) {
            Portfolio.AssetWeight memory assetWeight = assetWeights[i];

            uint256 amountInVault = _currentAmountInVault(assetWeight.asset);

            Portfolio.AssetInfo memory assetInfo = portfolio.getAssetInfo(assetWeight.asset);
            IPriceGetter priceGetter = IPriceGetter(assetInfo.priceGetter);

            uint256 usdcPriceDenominator = priceGetter.denominator();

            uint256 usdcPrice;
            if(sell)
                usdcPrice = priceGetter.getUsdcSellPrice();
            else
                usdcPrice = priceGetter.getUsdcBuyPrice();

            // in decimals: 18 + 18 - 18 => 18
            uint256 usdcPriceInVault = (amountInVault * usdcPrice) / usdcPriceDenominator;

            totalUsdcPrice += usdcPriceInVault;
        }

        return totalUsdcPrice;
    }


    function assetPricesForBalance() external view override returns (BalanceAssetPrices[] memory) {
        return assetPricesForBalance(address(0), 0);
    }

    /**
     * @param withdrawToken Token to withdraw
     * @param withdrawAmount Not normalized amount to withdraw
     */
    function assetPricesForBalance(address withdrawToken, uint256 withdrawAmount)
        public
        view
        override
        returns (BalanceAssetPrices[] memory)
    {
        if (withdrawToken != address(0)) {
            // normalize withdrawAmount to 18 decimals
            //TODO: denominator usage
            uint256 withdrawAmountDenominator = 10**(18 - IERC20Metadata(withdrawToken).decimals());
            withdrawAmount = withdrawAmount * withdrawAmountDenominator;
        }

        uint256 totalUsdcPrice = totalSellAssets();

        // 3. validate withdrawAmount
        // use `if` instead of `require` because less gas when need to build complex string for revert
        if (totalUsdcPrice < withdrawAmount) {
            revert(string(
                abi.encodePacked(
                    "Withdraw more than total: ",
                    Strings.toString(withdrawAmount),
                    " > ",
                    Strings.toString(totalUsdcPrice)
                )
            ));
        }

        // 4. correct total with withdrawAmount
        totalUsdcPrice = totalUsdcPrice - withdrawAmount;

        // 5. calc diffs to target values
        Portfolio.AssetWeight[] memory assetWeights = portfolio.getAllAssetWeights();
        uint256 count = assetWeights.length;
        BalanceAssetPrices[] memory assetPrices = new BalanceAssetPrices[](count);
        for (uint8 i = 0; i < count; i++) {
            Portfolio.AssetWeight memory assetWeight = assetWeights[i];
            int256 diffToTarget = 0;
            bool targetIsZero = false;
            (diffToTarget, targetIsZero) = _diffToTarget(totalUsdcPrice, assetWeight);
            // update diff for withdrawn token
            if (withdrawAmount > 0 && assetWeight.asset == withdrawToken) {
                diffToTarget = diffToTarget + int256(withdrawAmount);
            }
            assetPrices[i] = BalanceAssetPrices(
                assetWeight.asset,
                diffToTarget,
                targetIsZero
            );
        }

        return assetPrices;
    }

    /**
     * @param totalUsdcPrice - Total normilized to 10**18
     * @param assetWeight - Token address to calc
     * @return normalized to 10**18 signed diff amount and mark that mean that need sell all
     */
    function _diffToTarget(uint256 totalUsdcPrice, Portfolio.AssetWeight memory assetWeight)
        internal
        view
        returns (
            int256,
            bool
        )
    {
        address asset = assetWeight.asset;

        uint256 targetUsdcAmount = (totalUsdcPrice * assetWeight.targetWeight) /
            portfolio.TOTAL_WEIGHT();

        Portfolio.AssetInfo memory assetInfo = portfolio.getAssetInfo(asset);
        IPriceGetter priceGetter = IPriceGetter(assetInfo.priceGetter);

        uint256 usdcPriceDenominator = priceGetter.denominator();
        uint256 usdcBuyPrice = priceGetter.getUsdcBuyPrice();

        // in decimals: 18 * 18 / 18 => 18
        uint256 targetTokenAmount = (targetUsdcAmount * usdcPriceDenominator) / usdcBuyPrice;

        // normalize currentAmount to 18 decimals
        uint256 currentAmount = _currentAmountInVault(asset);

        bool targetIsZero;
        if (targetTokenAmount == 0) {
            targetIsZero = true;
        } else {
            targetIsZero = false;
        }

        int256 diff = int256(targetTokenAmount) - int256(currentAmount);
        return (diff, targetIsZero);
    }

    function _currentAmountInVault(address asset) internal view returns (uint256){
        // normalize currentAmount to 18 decimals
        uint256 currentAmount = IERC20(asset).balanceOf(address(vault));
        //TODO: denominator usage
        uint256 denominator = 10 ** (18 - IERC20Metadata(asset).decimals());
        currentAmount = currentAmount * denominator;
        return currentAmount;
    }




}
