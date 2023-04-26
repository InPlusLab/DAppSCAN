// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IProxyFactory {
    function clone(address _target) external returns(address);
}