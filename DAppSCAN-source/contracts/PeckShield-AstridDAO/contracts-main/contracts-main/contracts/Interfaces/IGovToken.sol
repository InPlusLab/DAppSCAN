// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Dependencies/IERC20.sol";

interface IGovToken is IERC20 {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}