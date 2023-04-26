// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "../TokenSale.sol";

contract TokenSaleMock is TokenSale {
    constructor(
        IERC20 _saleToken,
        uint256 _maticPrice,
        uint256 _usdcPrice,
        uint256 _maxBuyAmount,
        uint256 _cap,
        uint256 _releaseTime,
        uint256 _unlockTime
    )
        TokenSale(
            _saleToken,
            _maticPrice,
            _usdcPrice,
            _maxBuyAmount,
            _cap,
            _releaseTime,
            _unlockTime
        )
    {}

    function setUSDCAddress(address _newAdd) public onlyOwner {
        usdcAddress = _newAdd;
    }
}
