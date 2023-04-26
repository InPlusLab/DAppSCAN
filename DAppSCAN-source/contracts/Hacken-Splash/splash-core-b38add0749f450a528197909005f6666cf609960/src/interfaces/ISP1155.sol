// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/token/ERC1155/IERC1155.sol";

interface ISP1155 is IERC1155 {
  function mint(address to, uint256 id, uint256 amount, bytes memory data) external;
  function burn(address owner, uint256 id, uint256 number) external;
}