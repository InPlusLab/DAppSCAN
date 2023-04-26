// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import '../interfaces/IERC721Helpers.sol';
import '../OKLGWithdrawable.sol';

/**
 * @title NFTMintCostUSD
 * @dev Provide the cost for minting an NFT from Chainlink price feed data
 */
contract NFTMintCostUSD is IERC721Helpers, OKLGWithdrawable {
  AggregatorV3Interface internal priceFeed;
  uint256 public priceUSDCents;

  uint256 public discountAmountPercent = 25;
  mapping(address => bool) public discounted;

  constructor(address _priceFeed, uint256 _priceCents) {
    // https://docs.chain.link/docs/reference-contracts/
    // https://github.com/pcaversaccio/chainlink-price-feed/blob/main/README.md
    priceFeed = AggregatorV3Interface(_priceFeed);
    priceUSDCents = _priceCents;
  }

  function getPriceWei(uint256 _costUSDCents) public view returns (uint256) {
    // Creates a USD balance with 18 decimals
    // NOTE: We multiply by 10**16 because the input is in cents, not USD
    uint256 paymentUSD18 = 10**16 * _costUSDCents;

    // adding back 18 decimals to get returned value in wei
    return (10**18 * paymentUSD18) / getLatestETHPrice();
  }

  /**
   * Returns the latest ETH/USD price with returned value at 18 decimals
   * https://docs.chain.link/docs/get-the-latest-price/
   */
  function getLatestETHPrice() public view returns (uint256) {
    uint8 decimals = priceFeed.decimals();
    (, int256 price, , , ) = priceFeed.latestRoundData();
    return uint256(price) * (10**18 / 10**decimals);
  }

  function setPriceFeed(address _feedContract) external onlyOwner {
    priceFeed = AggregatorV3Interface(_feedContract);
  }

  function setPriceUSD(uint256 _priceUSDCents) external onlyOwner {
    priceUSDCents = _priceUSDCents;
  }

  function setDiscountAmountPercent(uint256 _percent) external onlyOwner {
    require(_percent <= 100, 'cannot be discounted more than 100%');
    discountAmountPercent = _percent;
  }

  function setDiscountedAddresses(address[] memory _wallets, bool _isDiscounted)
    external
    onlyOwner
  {
    for (uint256 _i = 0; _i < _wallets.length; _i++) {
      discounted[_wallets[_i]] = _isDiscounted;
    }
  }

  /**
   * getMintCost: get the amount in Wei of minting an NFT
   */
  function getMintCost(address _wallet)
    external
    view
    override
    returns (uint256)
  {
    if (priceUSDCents == 0) return 0;
    uint256 basePriceWei = getPriceWei(priceUSDCents);
    if (discounted[_wallet]) {
      return basePriceWei - ((basePriceWei * discountAmountPercent) / 100);
    }
    return basePriceWei;
  }
}
