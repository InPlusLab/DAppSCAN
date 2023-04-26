// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IBuyback {
    function buyback(address _token, uint256 _value) external returns (uint256 value);
}