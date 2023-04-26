// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {IGlobalAddressesProvider} from"../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {IAggregatorV2V3Interface} from "../../interfaces/IAggregatorV2V3Interface.sol";

/// @title ChainlinkProxyPriceProvider
/// @author Aave, SIGH Finance
/// @notice Proxy smart contract to get the price of an asset from a price source, with Chainlink Aggregator smart contracts as primary option
/// - If the returned price by a Chainlink aggregator is <= 0, the call is forwarded to a fallbackOracle

contract MockProxyPriceProvider is IPriceOracleGetter {

    IGlobalAddressesProvider public globalAddressesProvider;

    mapping(address => uint) assetPrices;

    mapping(address => IAggregatorV2V3Interface) private assetsSources;
    IPriceOracleGetter private fallbackOracle;

    event AssetSourceUpdated(address indexed asset, address indexed source);
    event FallbackOracleUpdated(address indexed fallbackOracle);

    modifier onlyLendingPoolManager {
        require(msg.sender == globalAddressesProvider.getLendingPoolManager(),"New Source / fallback oracle can only be set by the LendingPool Manager.");
        _;
    }

// #######################
// ##### CONSTRUCTOR #####
// #######################

    constructor( address globalAddressesProvider_ ) {
        globalAddressesProvider = IGlobalAddressesProvider(globalAddressesProvider_);
    }

// ####################################
// ##### SET THE PRICEFEED SOURCE #####
// ####################################

    function supportNewAsset(address asset_, uint price) public  {  //
        assetPrices[asset_] = price;
    }

//    /// @notice External function called by the Aave governance to set or replace sources of assets
//    /// @param _assets The addresses of the assets
//    /// @param _sources The address of the source of each asset
//    function setAssetSources(address[] calldata _assets, address[] calldata _sources) external onlyLendingPoolManager {
//        internalSetAssetsSources(_assets, _sources);
//    }

//    /// @notice Sets the fallbackOracle
//    /// - Callable only by the Aave governance
//    /// @param _fallbackOracle The address of the fallbackOracle
//    function setFallbackOracle(address _fallbackOracle) onlyLendingPoolManager external  {  //
//        internalSetFallbackOracle(_fallbackOracle);
//    }

// ##############################
// ##### INTERNAL FUNCTIONS #####
// ##############################

    /// @notice Internal function to set the sources for each asset
    /// @param _assets The addresses of the assets
    /// @param _sources The address of the source of each asset
    function internalSetAssetsSources(address[] memory _assets, address[] memory _sources) internal {
        require(_assets.length == _sources.length, "INCONSISTENT_PARAMS_LENGTH");
        for (uint256 i = 0; i < _assets.length; i++) {
            assetsSources[_assets[i]] = IAggregatorV2V3Interface(_sources[i]);
            emit AssetSourceUpdated(_assets[i], _sources[i]);
        }
    }

    /// @notice Internal function to set the fallbackOracle
    /// @param _fallbackOracle The address of the fallbackOracle
    function internalSetFallbackOracle(address _fallbackOracle) internal {
        fallbackOracle = IPriceOracleGetter(_fallbackOracle);
        emit FallbackOracleUpdated(_fallbackOracle);
    }

// ##########################
// ##### VIEW FUNCTIONS #####
// ##########################

    /// @notice Gets an asset price by address
    /// @param _asset The asset address
    function getAssetPrice(address _asset) public view override returns(uint256) {
        return assetPrices[_asset];
//        IAggregatorV2V3Interface source = assetsSources[_asset];
//        if (address(source) == address(0)) {                // If there is no registered source for the asset, call the fallbackOracle
//            return IPriceOracleGetter(fallbackOracle).getAssetPrice(_asset);
//        }
//        else {
//            int256 _price = IAggregatorV2V3Interface(source).latestAnswer();
//            if (_price > 0) {
//                return uint256(_price);
//            }
//            else {
//                return IPriceOracleGetter(fallbackOracle).getAssetPrice(_asset);
//            }
//        }
    }

    function getAssetPriceDecimals (address _asset) external view override returns(uint8) {
        return uint8(18);
//        IAggregatorV2V3Interface source = assetsSources[_asset];
//        uint8 decimals = IAggregatorV2V3Interface(source).decimals();
//        return decimals;
    }

    /// @notice Gets a list of prices from a list of assets addresses
    /// @param _assets The list of assets addresses
    function getAssetsPrices(address[] calldata _assets) external view returns(uint256[] memory) {
        uint256[] memory prices = new uint256[](_assets.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            prices[i] = getAssetPrice(_assets[i]);
        }
        return prices;
    }

    /// @notice Gets the address of the source for an asset address
    /// @param _asset The address of the asset
    /// @return address The address of the source
    function getSourceOfAsset(address _asset) external view returns(address) {
        return address(assetsSources[_asset]);
    }

    /// @notice Gets the address of the fallback oracle
    /// @return address The addres of the fallback oracle
    function getFallbackOracle() external view returns(address) {
        return address(fallbackOracle);
    }
}