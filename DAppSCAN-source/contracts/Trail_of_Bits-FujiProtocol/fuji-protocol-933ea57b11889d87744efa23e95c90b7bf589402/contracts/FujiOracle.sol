// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstracts/claimable/Claimable.sol";
import "./interfaces/chainlink/AggregatorV3Interface.sol";
import "./interfaces/IFujiOracle.sol";
import "./libraries/Errors.sol";

contract FujiOracle is IFujiOracle, Claimable {
  // mapping from asset address to its price feed oracle in USD - decimals: 8
  mapping(address => address) public usdPriceFeeds;

  constructor(address[] memory _assets, address[] memory _priceFeeds) Claimable() {
    require(_assets.length == _priceFeeds.length, Errors.ORACLE_INVALID_LENGTH);
    for (uint256 i = 0; i < _assets.length; i++) {
      usdPriceFeeds[_assets[i]] = _priceFeeds[i];
    }
  }

  function setPriceFeed(address _asset, address _priceFeed) public onlyOwner {
    usdPriceFeeds[_asset] = _priceFeed;
  }

  /// @dev Calculates the exchange rate n given decimals (_borrowAsset / _collateralAsset Exchange Rate)
  /// @param _collateralAsset the collateral asset, zero-address for USD
  /// @param _borrowAsset the borrow asset, zero-address for USD
  /// @param _decimals the decimals of the price output
  /// @return price The exchange rate of the given assets pair
  function getPriceOf(
    address _collateralAsset,
    address _borrowAsset,
    uint8 _decimals
  ) external view override returns (uint256 price) {
    price = 10**uint256(_decimals);

    if (_borrowAsset != address(0)) {
      price = price * _getUSDPrice(_borrowAsset);
    } else {
      price = price * (10**8);
    }

    if (_collateralAsset != address(0)) {
      price = price / _getUSDPrice(_collateralAsset);
    } else {
      price = price / (10**8);
    }
  }

  /// @dev Calculates the USD price of asset
  /// @param _asset the asset address
  /// @return price USD price of the give asset
  function _getUSDPrice(address _asset) internal view returns (uint256 price) {
    require(usdPriceFeeds[_asset] != address(0), Errors.ORACLE_NONE_PRICE_FEED);

    (, int256 latestPrice, , , ) = AggregatorV3Interface(usdPriceFeeds[_asset]).latestRoundData();

    price = uint256(latestPrice);
  }
}
