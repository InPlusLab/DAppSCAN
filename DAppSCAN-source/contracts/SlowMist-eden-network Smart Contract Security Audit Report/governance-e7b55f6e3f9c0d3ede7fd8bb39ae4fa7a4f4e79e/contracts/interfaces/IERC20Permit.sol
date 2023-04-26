// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IERC20Permit is IERC20 {
    function getDomainSeparator() external view returns (bytes32);
    function DOMAIN_TYPEHASH() external view returns (bytes32);
    function VERSION_HASH() external view returns (bytes32);
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function nonces(address) external view returns (uint);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}