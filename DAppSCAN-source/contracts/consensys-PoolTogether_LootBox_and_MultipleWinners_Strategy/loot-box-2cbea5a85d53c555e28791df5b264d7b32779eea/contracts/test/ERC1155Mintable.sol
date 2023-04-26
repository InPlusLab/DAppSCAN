// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract ERC1155Mintable is ERC1155 {

  constructor (
    string memory uri
  ) public ERC1155(uri) {
  }

  function mint(address to, uint256 id, uint256 amount, bytes calldata data) external returns (address) {
    _mint(to, id, amount, data);
  }

}
