// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20 {

  constructor (
    string memory name,
    string memory symbol
  ) public ERC20(name, symbol) {
  }

  function mint(address to, uint256 amount) external returns (address) {
    _mint(to, amount);
  }

}
