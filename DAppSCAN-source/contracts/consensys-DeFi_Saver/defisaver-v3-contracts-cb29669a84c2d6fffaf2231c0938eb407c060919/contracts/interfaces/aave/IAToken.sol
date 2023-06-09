// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

abstract contract IAToken {
    function redeem(uint256 _amount) external virtual;
    function balanceOf(address _owner) external virtual view returns (uint256 balance);
}
