// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./interfaces/IPrice.sol";

contract MockOracle is IPrice {
    int256 price;
    string public name;
    address operator;

    constructor(int256 price_, string memory name_) {
        price = price_;
        operator = msg.sender;
        name = name_;
    }

    function setPrice(int256 price_) public {
        require(msg.sender == operator, "IA");
        price = price_;
    }

    /**
     * Returns the latest price
     */
    function getThePrice() external view override returns (int256) {
        return price;
    }
}
