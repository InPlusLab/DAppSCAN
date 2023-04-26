// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAuthManager {
    function has(bytes32 role, address member) external view returns (bool);

    function add(bytes32 role, address member) external;

    function remove(bytes32 role, address member) external;
}