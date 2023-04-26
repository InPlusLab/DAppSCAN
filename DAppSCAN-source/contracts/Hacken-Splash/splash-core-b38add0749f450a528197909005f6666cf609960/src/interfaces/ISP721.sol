// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/token/ERC721/IERC721.sol";

interface ISP721 is IERC721 {
  function safeMint(address to, uint256 id) external;
}