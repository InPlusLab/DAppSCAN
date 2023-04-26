// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/token/ERC20/ERC20.sol";

abstract contract ISP20 is ERC20 {
  function mint(address to, uint256 amount) virtual external;
}