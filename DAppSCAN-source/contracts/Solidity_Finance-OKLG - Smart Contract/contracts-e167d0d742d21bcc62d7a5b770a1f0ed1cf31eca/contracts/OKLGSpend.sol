// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import './interfaces/IOKLGSpend.sol';
import './OKLGWithdrawable.sol';

/**
 * @title OKLGSpend
 * @dev Logic for spending OKLG on products in the product ecosystem.
 */
contract OKLGSpend is IOKLGSpend, OKLGWithdrawable {
  address payable private constant DEAD_WALLET =
    payable(0x000000000000000000000000000000000000dEaD);
  address payable public paymentWallet =
    payable(0x000000000000000000000000000000000000dEaD);

  AggregatorV3Interface internal priceFeed;

  uint256 public totalSpentWei = 0;
  mapping(uint8 => uint256) public defaultProductPriceUSD;
  mapping(address => uint256) public overrideProductPriceUSD;
  mapping(address => bool) public removeCost;
  event Spend(address indexed user, address indexed product, uint256 value);

  constructor(address _linkPriceFeedContract) {
    // https://docs.chain.link/docs/reference-contracts/
    // https://github.com/pcaversaccio/chainlink-price-feed/blob/main/README.md
    priceFeed = AggregatorV3Interface(_linkPriceFeedContract);
  }

  function getProductCostWei(uint256 _productCostUSD)
    public
    view
    returns (uint256)
  {
    // Creates a USD balance with 18 decimals
    uint256 paymentUSD18 = 10**18 * _productCostUSD;

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

  function setPaymentWallet(address _newPaymentWallet) external onlyOwner {
    paymentWallet = payable(_newPaymentWallet);
  }

  function setDefaultProductUSDPrice(uint8 _product, uint256 _priceUSD)
    external
    onlyOwner
  {
    defaultProductPriceUSD[_product] = _priceUSD;
  }

  function setDefaultProductPricesUSDBulk(
    uint8[] memory _productIds,
    uint256[] memory _pricesUSD
  ) external onlyOwner {
    require(
      _productIds.length == _pricesUSD.length,
      'arrays need to be the same length'
    );
    for (uint256 _i = 0; _i < _productIds.length; _i++) {
      defaultProductPriceUSD[_productIds[_i]] = _pricesUSD[_i];
    }
  }

  function setOverrideProductPriceUSD(address _productCont, uint256 _priceUSD)
    external
    onlyOwner
  {
    overrideProductPriceUSD[_productCont] = _priceUSD;
  }

  function setOverrideProductPricesUSDBulk(
    address[] memory _contracts,
    uint256[] memory _pricesUSD
  ) external onlyOwner {
    require(
      _contracts.length == _pricesUSD.length,
      'arrays need to be the same length'
    );
    for (uint256 _i = 0; _i < _contracts.length; _i++) {
      overrideProductPriceUSD[_contracts[_i]] = _pricesUSD[_i];
    }
  }

  function setRemoveCost(address _productCont, bool _isRemoved)
    external
    onlyOwner
  {
    removeCost[_productCont] = _isRemoved;
  }

  /**
   * spendOnProduct: used by an OKLG product for a user to spend native token on usage of a product
   */
  function spendOnProduct(address _payor, uint8 _product)
    external
    payable
    override
  {
    if (removeCost[msg.sender]) return;

    uint256 _productCostUSD = overrideProductPriceUSD[msg.sender] > 0
      ? overrideProductPriceUSD[msg.sender]
      : defaultProductPriceUSD[_product];
    if (_productCostUSD == 0) return;

    uint256 _productCostWei = getProductCostWei(_productCostUSD);

    require(
      msg.value >= _productCostWei,
      'not enough ETH sent to pay for product'
    );
    address payable _paymentWallet = paymentWallet == DEAD_WALLET ||
      paymentWallet == address(0)
      ? payable(owner())
      : paymentWallet;
    _paymentWallet.call{ value: _productCostWei }('');
    _refundExcessPayment(_productCostWei);
    totalSpentWei += _productCostWei;
    emit Spend(msg.sender, _payor, _productCostWei);
  }

  function _refundExcessPayment(uint256 _productCost) internal {
    uint256 excess = msg.value - _productCost;
    if (excess > 0) {
      payable(msg.sender).call{ value: excess }('');
    }
  }
}
