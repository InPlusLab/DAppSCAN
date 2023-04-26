pragma solidity ^0.5.16;

import "../../contracts/PriceOracle.sol";

contract FixedPriceOracle is PriceOracle {
    uint public price;

    constructor(uint _price) public {
        price = _price;
    }

    function getUnderlyingPrice(RToken rToken) public view returns (uint) {
        rToken;
        return price;
    }

    function assetPrices(address asset) public view returns (uint) {
        asset;
        return price;
    }
}
