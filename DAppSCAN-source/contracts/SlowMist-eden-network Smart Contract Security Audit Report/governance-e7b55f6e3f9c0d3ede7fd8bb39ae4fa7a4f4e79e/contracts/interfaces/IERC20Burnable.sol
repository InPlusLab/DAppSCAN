// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IERC20Burnable is IERC20 {
    function burn(uint256 amount) external returns (bool);
}
