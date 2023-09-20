// SPDX-License-Identifier: MIT
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IYVault} from "./IYVault.sol";

import "hardhat/console.sol";

/// @title Yearn Chainlink pricefeed adapter
// SWC-135-Code With No Effects: L18 - L69
contract YearnPriceFeed is Proxy {
    using SafeMath for uint256;
    AggregatorV3Interface public priceFeed;
    IYVault public yVault;
    uint256 decimalsDivider;

    constructor(address _yVault, address _priceFeed) {
        yVault = IYVault(_yVault);
        priceFeed = AggregatorV3Interface(_priceFeed);
        decimalsDivider = 10**yVault.decimals();
    }

    function _implementation() internal view override returns (address) {
        return address(yVault);
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed
        .getRoundData(_roundId);
        answer = int256(
            yVault.pricePerShare().mul(uint256(answer)).div(decimalsDivider)
        );
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed
        .latestRoundData();
        answer = int256(
            yVault.pricePerShare().mul(uint256(answer)).div(decimalsDivider)
        );
    }
}
