// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

interface IOwnable {
    function owner() external view returns (address);
    function renounceOwnership() external;
    function transferOwnership(address newOwner) external;
}