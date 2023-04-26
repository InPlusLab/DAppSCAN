// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IReadProxy {
    function target() external view returns (address);
}
