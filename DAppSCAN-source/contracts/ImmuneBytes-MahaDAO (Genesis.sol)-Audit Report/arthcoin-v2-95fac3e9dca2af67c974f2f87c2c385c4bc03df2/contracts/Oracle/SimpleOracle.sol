// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from '../access/Ownable.sol';
import {ISimpleOracle} from './ISimpleOracle.sol';

contract SimpleOracle is Ownable, ISimpleOracle {
    string public name;
    uint256 public price = 1e18;

    constructor(string memory _name, uint256 _price) {
        name = _name;
        price = _price;
    }

    function getPrice() public view override returns (uint256) {
        return price;
    }

    function setPrice(uint256 _price) public onlyOwner {
        require(_price >= 0, 'Oracle: price cannot be < 0');
        price = _price;
        emit PriceChange(block.timestamp, _price);
    }

    event PriceChange(uint256 timestamp, uint256 price);
}
