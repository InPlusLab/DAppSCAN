// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import './OKLGAffiliate.sol';

/**
 * @title OKLGBuybot
 * @dev Logic for spending OKLG on products in the product ecosystem.
 */
contract OKLGBuybot is OKLGAffiliate {
  AggregatorV3Interface internal priceFeed;

  uint256 public totalSpentWei = 0;
  uint256 public paidPricePerDayUsd = 25;
  mapping(address => uint256) public overridePricePerDayUSD;
  mapping(address => bool) public removeCost;
  event SetupBot(
    address indexed user,
    address token,
    string client,
    string channel,
    uint256 expiration
  );
  event SetupBotAdmin(
    address indexed user,
    address token,
    string client,
    string channel,
    uint256 expiration
  );
  event DeleteBot(
    address indexed user,
    address token,
    string client,
    string channel
  );

  struct Buybot {
    address token;
    string client; // telegram, discord, etc.
    string channel;
    bool isPaid;
    uint256 minThresholdUsd;
    // lpPairAltToken?: string; // if blank, assume the other token in the pair is native (ETH, BNB, etc.)
    uint256 expiration; // unix timestamp of expiration, or 0 if no expiration
  }
  mapping(bytes32 => Buybot) public buybotConfigs;
  bytes32[] public buybotConfigsList;

  constructor(address _linkPriceFeedContract) {
    // https://docs.chain.link/docs/reference-contracts/
    // https://github.com/pcaversaccio/chainlink-price-feed/blob/main/README.md
    priceFeed = AggregatorV3Interface(_linkPriceFeedContract);
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

  function setOverridePricePerDayUSD(address _wallet, uint256 _priceUSD)
    external
    onlyOwner
  {
    overridePricePerDayUSD[_wallet] = _priceUSD;
  }

  function setOverridePricesPerDayUSDBulk(
    address[] memory _contracts,
    uint256[] memory _pricesUSD
  ) external onlyOwner {
    require(
      _contracts.length == _pricesUSD.length,
      'arrays need to be the same length'
    );
    for (uint256 _i = 0; _i < _contracts.length; _i++) {
      overridePricePerDayUSD[_contracts[_i]] = _pricesUSD[_i];
    }
  }

  function setRemoveCost(address _wallet, bool _isRemoved) external onlyOwner {
    removeCost[_wallet] = _isRemoved;
  }

  function getId(
    address _token,
    string memory _client,
    string memory _channel
  ) public pure returns (bytes32) {
    return sha256(abi.encodePacked(_token, _client, _channel));
  }

  function setupBot(
    address _token,
    string memory _client,
    string memory _channel,
    bool _isPaid,
    uint256 _minThresholdUsd,
    address _referrer
  ) external payable {
    require(msg.value >= 0, 'must send some ETH to pay for bot');

    uint256 _costPerDayUSD = overridePricePerDayUSD[msg.sender] > 0
      ? overridePricePerDayUSD[msg.sender]
      : paidPricePerDayUsd;

    if (_isPaid && !removeCost[msg.sender]) {
      pay(msg.sender, _referrer, msg.value);

      totalSpentWei += msg.value;
      _costPerDayUSD = 0;
    }

    uint256 _daysOfService18 = 30;
    if (_costPerDayUSD > 0) {
      uint256 _costPerDayUSD18 = _costPerDayUSD * 10**18;
      uint256 _ethPriceUSD18 = getLatestETHPrice();
      _daysOfService18 =
        ((msg.value * 10**18) * _ethPriceUSD18) /
        _costPerDayUSD18;
    }

    uint256 _secondsOfService = (_daysOfService18 * 24 * 60 * 60) / 10**18;
    bytes32 _id = getId(_token, _client, _channel);

    Buybot storage _bot = buybotConfigs[_id];
    if (_bot.expiration == 0) {
      buybotConfigsList.push(_id);
    }
    uint256 _start = _bot.expiration < block.timestamp
      ? block.timestamp
      : _bot.expiration;

    _bot.token = _token;
    _bot.isPaid = _isPaid;
    _bot.client = _client;
    _bot.channel = _channel;
    _bot.minThresholdUsd = _minThresholdUsd;
    _bot.expiration = _start + _secondsOfService;
    emit SetupBot(msg.sender, _token, _client, _channel, _bot.expiration);
  }

  function setupBotAdmin(
    address _token,
    string memory _client,
    string memory _channel,
    bool _isPaid,
    uint256 _minThresholdUsd,
    uint256 _expiration
  ) external onlyOwner {
    bytes32 _id = getId(_token, _client, _channel);
    Buybot storage _bot = buybotConfigs[_id];
    if (_bot.expiration == 0) {
      buybotConfigsList.push(_id);
    }
    _bot.token = _token;
    _bot.isPaid = _isPaid;
    _bot.client = _client;
    _bot.channel = _channel;
    _bot.minThresholdUsd = _minThresholdUsd;
    _bot.expiration = _expiration;
    emit SetupBotAdmin(msg.sender, _token, _client, _channel, _bot.expiration);
  }

  function deleteBot(
    address _token,
    string memory _client,
    string memory _channel
  ) external onlyOwner {
    bytes32 _id = getId(_token, _client, _channel);
    delete buybotConfigs[_id];
    for (uint256 _i = 0; _i < buybotConfigsList.length; _i++) {
      if (buybotConfigsList[_i] == _id) {
        buybotConfigsList[_i] = buybotConfigsList[buybotConfigsList.length - 1];
        buybotConfigsList.pop();
      }
    }
    emit DeleteBot(msg.sender, _token, _client, _channel);
  }
}
