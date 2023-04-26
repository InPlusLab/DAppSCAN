// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

interface IPrice {
    function getThePrice() external view returns (int256 price);
}
