// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../price_getters/AbstractPriceGetter.sol";
import "../connectors/curve/interfaces/iCurvePool.sol";

contract A3CrvPriceGetter is AbstractPriceGetter, Ownable {
    iCurvePool public pool;

    event UpdatedPool(address pool);

    function setPool(address _pool) public onlyOwner {
        require(_pool != address(0), "Zero address not allowed");
        pool = iCurvePool(_pool);
        emit UpdatedPool(_pool);
    }

    function getUsdcBuyPrice() external view override returns (uint256) {
        return pool.get_virtual_price();
    }

    function getUsdcSellPrice() external view override returns (uint256) {
        return pool.get_virtual_price();
    }
}
