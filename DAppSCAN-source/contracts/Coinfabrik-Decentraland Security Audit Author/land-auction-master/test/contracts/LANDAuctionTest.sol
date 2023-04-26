pragma solidity ^0.4.24;

import "../../contracts/auction/LANDAuction.sol";


contract LANDAuctionTest is LANDAuction {
    constructor(
        uint256[] _xPoints, 
        uint256[] _yPoints, 
        uint256 _startTime,
        uint256 _landsLimitPerBid,
        uint256 _gasPriceLimit,
        ERC20 _manaToken, 
        LANDRegistry _landRegistry,
        address _dex
    ) public LANDAuction(
        _xPoints, 
        _yPoints, 
        _startTime,
        _landsLimitPerBid,
        _gasPriceLimit,
        _manaToken,
        _landRegistry, 
        _dex
    ) {}

    function getPrice(uint256 _value) public view returns (uint256) {
        if (startTime == 0) {
            return initialPrice;
        } else {
            if (_value >= duration) {
                return endPrice;
            }
            return _getPrice(_value);
        }
    }
}