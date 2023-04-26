// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IRToken.sol";

contract ChainlinkPriceFeed is Ownable {
    using FixedPoint for *;

    struct TokenConfig {
        address rToken;
        address underlying;
        bytes32 symbolHash;
        uint256 baseUnit;
        address chainlinkPriceFeed;
    }

    struct Observation {
        uint256 timestamp;
        uint256 acc;
    }

    uint256 public constant PRECISION = 1e18;

    mapping(address => TokenConfig) public getTokenConfigFromRToken;
    mapping(bytes32 => address) public getRTokenFromSymbolHash;
    mapping(address => address) public getRTokenFromUnderlying;

    function getUnderlyingPrice(IRToken _rToken) external view returns (uint256) {
        TokenConfig storage config = getTokenConfigFromRToken[address(_rToken)];
         // IronController needs prices in the format: ${raw price} * 1e(36 - baseUnit)
         // Since the prices in this view have 6 decimals, we must scale them by 1e(36 - 6 - baseUnit)
        return 1e18 * getFromChainlink(config.chainlinkPriceFeed) / config.baseUnit;
    }

    function setTokenConfig(
        address _rToken,
        address _underlying,
        string memory _symbol,
        uint256 _decimals,
        address _chainlinkPriceFeed
    ) external onlyOwner {
        require(getRTokenFromUnderlying[_underlying] == address(0), "RToken & underlying existed");
        require(_chainlinkPriceFeed != address(0), "!chainlink");
        bytes32 symbolHash = keccak256(abi.encodePacked(_symbol));

        TokenConfig storage _newToken = getTokenConfigFromRToken[_rToken];
        _newToken.rToken = _rToken;
        _newToken.underlying = _underlying;
        _newToken.baseUnit = 10**_decimals;
        _newToken.symbolHash = symbolHash;
        _newToken.chainlinkPriceFeed = _chainlinkPriceFeed;

        getRTokenFromUnderlying[_newToken.underlying] = _rToken;
        getRTokenFromSymbolHash[_newToken.symbolHash] = _rToken;
    }

    function price(string calldata _symbol) external view returns (uint256) {
        TokenConfig memory config = getTokenConfigBySymbol(_symbol);
        return getFromChainlink(config.chainlinkPriceFeed);
    }

    /**
     * @return price in USD with 6 decimals
     */
    function getFromChainlink(address _chainlinkPriceFeed) internal view returns (uint256) {
        assert(_chainlinkPriceFeed != address(0));
        AggregatorV3Interface _priceFeed = AggregatorV3Interface(_chainlinkPriceFeed);
        (, int256 _price, , , ) = _priceFeed.latestRoundData();
        uint8 _decimals = _priceFeed.decimals();
        return (uint256(_price) * PRECISION) / (10**_decimals);
    }

    function getTokenConfigBySymbolHash(bytes32 _symbolHash) internal view returns (TokenConfig memory) {
        address rToken = getRTokenFromSymbolHash[_symbolHash];
        require(rToken != address(0), "token config not found");
        return getTokenConfigFromRToken[rToken];
    }

    function getTokenConfigBySymbol(string memory symbol) public view returns (TokenConfig memory) {
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
        return getTokenConfigBySymbolHash(symbolHash);
    }
}
