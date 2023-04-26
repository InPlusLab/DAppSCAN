pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "./IOracle.sol";

// for unit testing only
contract MockOracle is IOracle {
    uint256 public price = 3000e8;

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function getPrice(address feed) external view override returns (uint256)  {
        return price;
    }
}
