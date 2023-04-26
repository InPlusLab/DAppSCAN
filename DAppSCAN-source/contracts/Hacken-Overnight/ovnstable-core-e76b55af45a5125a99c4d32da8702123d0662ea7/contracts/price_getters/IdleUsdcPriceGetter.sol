// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../price_getters/AbstractPriceGetter.sol";
import "../connectors/idle/interfaces/IIdleToken.sol";

contract IdleUsdcPriceGetter is AbstractPriceGetter, Ownable {

    IIdleToken public idleToken;

    function setIdleToken(address _idleToken) public onlyOwner {
        require(_idleToken != address(0), "Zero address not allowed");
        idleToken = IIdleToken(_idleToken);
    }

    function getUsdcBuyPrice() external view override returns (uint256) {
        return idleToken.tokenPrice() * (10**12);
    }

    function getUsdcSellPrice() external view override returns (uint256) {
        return idleToken.tokenPrice() * (10**12);
    }
}
