// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeMath} from '../utils/math/SafeMath.sol';

import {UniswapV2Library} from '../Uniswap/UniswapV2Library.sol';
import {IUniswapPairOracle} from '../Oracle/IUniswapPairOracle.sol';

contract MockUniswapPairOracle is IUniswapPairOracle {
    using SafeMath for uint256;

    uint256 epoch;
    uint256 period = 1;

    uint256 public price = 1e18;
    bool public error;

    uint256 startTime;

    constructor() {
        startTime = block.timestamp;
    }

    function setEpoch(uint256 _epoch) public {
        epoch = _epoch;
    }

    function setStartTime(uint256 _startTime) public {
        startTime = _startTime;
    }

    function setPeriod(uint256 _period) public override {
        period = _period;
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }

    function setRevert(bool _error) public {
        error = _error;
    }

    function update() external override {
        require(!error, 'Oracle: mocked error');
        emit Updated(0, 0);
    }

    function consult(address, uint256 amountIn)
        external
        view
        override
        returns (uint256)
    {
        return price.mul(amountIn).div(1e18);
    }

    function pairFor(
        address factory,
        address tokenA,
        address tokenB
    ) external view returns (address lpt) {
        return UniswapV2Library.pairFor(factory, tokenA, tokenB);
    }

    function setOwner(address _ownerAddress) external override {}

    function setTimelock(address _timelockAddress) external override {}

    function setConsultLeniency(uint256 _consultLeniency) external override {}

    function setAllowStaleConsults(bool _allowStaleConsults)
        external
        override
    {}

    function canUpdate() external pure override returns (bool) {
        return true;
    }

    event Updated(uint256 price0CumulativeLast, uint256 price1CumulativeLast);
}
