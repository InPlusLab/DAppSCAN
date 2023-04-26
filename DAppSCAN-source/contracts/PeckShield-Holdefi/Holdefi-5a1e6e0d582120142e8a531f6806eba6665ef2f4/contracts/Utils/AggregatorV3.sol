// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract AggregatorV3 is AggregatorV3Interface {

    uint8  dec;
    int256 price;
    string  desc = "";
    uint256 vers = 1;

    constructor(uint8 _decimals) public {
        dec = _decimals;
    }

    function decimals() external override virtual view  returns (uint8) {
        return dec;
    }

    function description() external override virtual view returns (string memory) {
        return desc;
    }

    function version() external override virtual view returns (uint256) {
        return vers;
    }

    function getRoundData(uint80 _roundId)
        external
        override
        virtual
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, price, 1, 1, 1);
    }

    function latestRoundData()
        external
        override
        virtual
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, price, 1, 1, 1);
    }

    function setPrice(int256 _price) public {
        price = _price;
    }

    function setDecimals(uint8 _decimals) public {
        dec = _decimals;
    }
}
