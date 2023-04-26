// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenMock is ERC20 {
  constructor()
    ERC20('FOO', 'FOO') public {
      _mint(msg.sender, 1000 * 10**18);
  }
}
