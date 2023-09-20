// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

import "@chainlink/contracts/src/v0.5/interfaces/AggregatorV3Interface.sol";

import "./external/mstable/IMasset.sol";

/**
 * @title RariFundPriceConsumer
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice RariFundPriceConsumer retrieves stablecoin prices from Chainlink's public price feeds (used by RariFundManager and RariFundController).
 */
contract RariFundPriceConsumer is Initializable, Ownable {
    using SafeMath for uint256;

    /**
     * @dev Chainlink price feed for DAI/USD.
     */
    AggregatorV3Interface private _daiUsdPriceFeed;
    
    /**
     * @dev Chainlink price feed for ETH/USD.
     */
    //  SWC-109-Uninitialized Storage Pointer: L31
    AggregatorV3Interface private _ethUsdPriceFeed;

    /**
     * @dev Chainlink price feeds for ETH-based pairs.
     */
    mapping(string => AggregatorV3Interface) private _ethBasedPriceFeeds;

    /**
     * @dev mStable mUSD token address.
     */
    address constant private MUSD = 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5;

    /**
     * @dev Initializer that sets supported ERC20 contract addresses and price feeds for each supported token.
     */
    function initialize(bool _allCurrenciesPeggedTo1Usd) public initializer {
        // Initialize owner
        Ownable.initialize(msg.sender);

        // Initialize allCurrenciesPeggedTo1Usd
        allCurrenciesPeggedTo1Usd = _allCurrenciesPeggedTo1Usd;

        // Initialize price feeds
        _daiUsdPriceFeed = AggregatorV3Interface(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);
        _ethUsdPriceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        _ethBasedPriceFeeds["USDC"] = AggregatorV3Interface(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);
        _ethBasedPriceFeeds["USDT"] = AggregatorV3Interface(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46);
        _ethBasedPriceFeeds["TUSD"] = AggregatorV3Interface(0x3886BA987236181D98F2401c507Fb8BeA7871dF2);
        _ethBasedPriceFeeds["BUSD"] = AggregatorV3Interface(0x614715d2Af89E6EC99A233818275142cE88d1Cfd);
        _ethBasedPriceFeeds["sUSD"] = AggregatorV3Interface(0x8e0b7e6062272B5eF4524250bFFF8e5Bd3497757);
    }

    /**
     * @dev Retrives the latest DAI/USD price.
     */
    function getDaiUsdPrice() internal view returns (uint256) {
        (, int256 price, , , ) = _daiUsdPriceFeed.latestRoundData();
        return price >= 0 ? uint256(price).mul(1e10) : 0;
    }

    /**
     * @dev Retrives the latest ETH/USD price.
     */
    function getEthUsdPrice() internal view returns (uint256) {
        (, int256 price, , , ) = _ethUsdPriceFeed.latestRoundData();
        return price >= 0 ? uint256(price).mul(1e10) : 0;
    }

    /**
     * @dev Retrives the latest price of an ETH-based pair.
     */
    function getPriceInEth(string memory currencyCode) internal view returns (uint256) {
        (, int256 price, , , ) = _ethBasedPriceFeeds[currencyCode].latestRoundData();
        return price >= 0 ? uint256(price) : 0;
    }

    /**
     * @dev Retrives the latest mUSD/USD price given the prices of the underlying bAssets.
     */
    function getMUsdUsdPrice(uint256[] memory bAssetUsdPrices) internal view returns (uint256) {
        (, IMasset.BassetData[] memory bAssetData) = IMasset(MUSD).getBassets();
        require(bAssetData.length == 4, "mUSD underlying bAsset data length not equal to bAsset USD prices length.");
        uint256 usdSupplyScaled = 0;
        for (uint256 i = 0; i < bAssetData.length; i++) usdSupplyScaled = usdSupplyScaled.add(uint256(bAssetData[i].vaultBalance).mul(uint256(bAssetData[i].ratio)).div(1e8).mul(bAssetUsdPrices[i]));
        return usdSupplyScaled.div(IERC20(MUSD).totalSupply());
    }

    /**
     * @notice Returns the price of each supported currency in USD (scaled by 1e18).
     */
    function getCurrencyPricesInUsd() external view returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](7);

        // If all pegged to $1
        if (allCurrenciesPeggedTo1Usd) {
            for (uint256 i = 0; i < 7; i++) prices[i] = 1e18;
            return prices;
        }

        // Get bAsset prices and mUSD price
        uint256 ethUsdPrice = getEthUsdPrice();
        prices[0] = getPriceInEth("sUSD").mul(ethUsdPrice).div(1e18);
        prices[1] = getPriceInEth("USDC").mul(ethUsdPrice).div(1e18);
        prices[2] = getDaiUsdPrice();
        prices[3] = getPriceInEth("USDT").mul(ethUsdPrice).div(1e18);
        prices[6] = getMUsdUsdPrice(prices);

        // Reorder bAsset prices to match _supportedCurrencies
        prices[5] = prices[0]; // Set prices[5] to sUSD
        prices[0] = prices[2]; // Set prices[0] to DAI
        prices[2] = prices[3]; // Set prices[2] to USDT

        // Get other prices
        prices[3] = getPriceInEth("TUSD").mul(ethUsdPrice).div(1e18);
        prices[4] = getPriceInEth("BUSD").mul(ethUsdPrice).div(1e18);

        // Return prices array
        return prices;
    }

    /**
     * @notice Boolean indicating if all currencies are stablecoins pegged to the value of $1.
     */
    bool public allCurrenciesPeggedTo1Usd;

    /**
     * @dev Admin function to peg all stablecoin prices to $1.
     */
    function set1UsdPegOnAllCurrencies(bool enabled) external onlyOwner {
        require(allCurrenciesPeggedTo1Usd != enabled, "$1 USD peg status already set to the requested value.");
        allCurrenciesPeggedTo1Usd = enabled;
    }
}
