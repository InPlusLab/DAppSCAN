// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
  constructor(
    string memory name,
    string memory symbol,
    uint8 decimals,
    uint256 supply
  ) public ERC20(name, symbol) {
    _mint(msg.sender, supply);
    _setupDecimals(decimals);
  }

  function mockWithdrawErc20(address token, uint256 amount) public {
    ERC20(token).transfer(msg.sender, amount);
  }

  function mint(address account, uint256 amount) public {
    _mint(account, amount);
  }

  function burn(uint256 amount) public {
    _burn(msg.sender, amount);
  }
}
