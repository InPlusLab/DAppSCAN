// SPDX-License-Identifier: BSL-1.1
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;

import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

import {AddressProvider} from "../core/AddressProvider.sol";

import {Constants} from "../libraries/helpers/Constants.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import "hardhat/console.sol";
import {ACLTrait} from "../core/ACLTrait.sol";

 /// @title Price Oracle based on Chainlink's price feeds
 /// @notice Works as router and provide cross rates using converting via ETH
 ///
 /// More: https://dev.gearbox.fi/developers/priceoracle
contract PriceOracle is ACLTrait, IPriceOracle {
    using SafeMath for uint256;

    // Address of WETH token
    address public wethAddress;

    // token => priceFeed
    mapping(address => address) public priceFeeds;

    // token => decimals multiplier
    mapping(address => uint256) public decimalsMultipliers;
    mapping(address => uint256) public decimalsDividers;

    constructor(address addressProvider) ACLTrait(addressProvider) {
        wethAddress = AddressProvider(addressProvider).getWethToken();
        decimalsMultipliers[wethAddress] = 1;
        decimalsDividers[wethAddress] = Constants.WAD;
    }

    /// @dev Sets price feed if it doesn't exist. If price feed is already set, it changes nothing
    /// This logic is done to protect Gearbox from priceOracle attack
    /// when potential attacker can get access to price oracle, change them to fraud ones
    /// and then liquidate all funds
    /// @param token Address of token
    /// @param priceFeed Address of chainlink price feed token => Eth
    function addPriceFeed(address token, address priceFeed)
        external
        override
        configuratorOnly
    {
        // T:[PO-5]
        if (priceFeeds[token] == address(0)) {
            priceFeeds[token] = priceFeed;
            uint256 decimals = ERC20(token).decimals();

            require(
                decimals <= 18,
                Errors.PO_TOKENS_WITH_DECIMALS_MORE_18_ISNT_ALLOWED
            ); // T:[PO-3]

            decimalsMultipliers[token] = 10**(18 - decimals);
            decimalsDividers[token] = 10**(36 - decimals);
            emit NewPriceFeed(token, priceFeed); // T:[PO-4]
        }
    }

    /// @dev Converts one asset into another using price feed rate. Reverts if price feed doesn't exist
    /// @param amount Amount to convert
    /// @param tokenFrom Token address converts from
    /// @param tokenTo Token address - converts to
    /// @return Amount converted to tokenTo asset
    function convert(
        uint256 amount,
        address tokenFrom,
        address tokenTo
    ) external view override returns (uint256) {
        return
            amount
                .mul(decimalsMultipliers[tokenFrom])
                .mul(getLastPrice(tokenFrom, tokenTo))
                .div(decimalsDividers[tokenTo]); // T:[PO-8]
    }

    /// @dev Gets token rate with 18 decimals. Reverts if priceFeed doesn't exist
    /// @param tokenFrom Converts from token address
    /// @param tokenTo Converts to token address
    /// @return Rate in WAD format
    function getLastPrice(address tokenFrom, address tokenTo)
        public
        view
        override
        returns (uint256)
    {
        if (tokenFrom == tokenTo) return Constants.WAD; // T:[PO-1]

        // price = wad * price[ETH] / price[token_to] = wad^2 / price[token_to]
        if (tokenFrom == wethAddress) {
            return Constants.WAD.mul(Constants.WAD).div(_getPrice(tokenTo)); // T:[PO-6]
        }

        // price = wad * price[token_from] / price[ETH] = wad * price[token_from] / wad = price[token_from]
        if (tokenTo == wethAddress) {
            return _getPrice(tokenFrom); // T:[PO-6]
        }

        return Constants.WAD.mul(_getPrice(tokenFrom)).div(_getPrice(tokenTo)); // T:[PO-7]
    }

    /// @dev Returns rate to ETH in WAD format
    /// @param token Token converts from
    function _getPrice(address token) internal view returns (uint256) {
        require(
            priceFeeds[token] != address(0),
            Errors.PO_PRICE_FEED_DOESNT_EXIST
        ); // T:[PO-9]

        (
            ,
            //uint80 roundID,
            int256 price, //uint startedAt, //uint timeStamp,
            ,
            ,

        ) =
            //uint80 answeredInRound
            AggregatorV3Interface(priceFeeds[token]).latestRoundData(); // T:[PO-6]
        return uint256(price);
    }
}
