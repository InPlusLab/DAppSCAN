// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.1;

import "../interfaces/IAaveLendingPool.sol";
import "./MockToken.sol";

contract MockAToken is MockToken {
    IERC20 public token;

    bool public revertRedeem;

    constructor(address _token) MockToken("MockAToken", "MATKN") public {
        token = IERC20(_token);
    }

    function redeem(uint256 _amount) external {
        require(!revertRedeem, "Reverted");

        if(_amount == uint256(-1)) {
            _amount = balanceOf(msg.sender);
        }

        _burn(msg.sender, _amount);
        require(token.transfer(msg.sender, _amount), "Transfer failed");
    }

    function setRevertRedeem(bool _doRevert) external {
        revertRedeem = _doRevert;
    }
}