// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/token/ERC20/ERC20.sol";
import "oz-contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "../utils/Errors.sol";
import "../interfaces/IRegistry.sol";

contract SPLASH is ERC20, ERC20Burnable, ISP20 {
  IRegistry registry;

  modifier authorized() {
    require(registry.authorized(msg.sender), Errors.NOT_AUTHORIZED);
    _;
  }

  constructor(IRegistry registryAddress) ERC20("SPLASH", "SPLASH") {
    _mint(msg.sender, 21000000 * 10**decimals());

    registry = IRegistry(registryAddress);
  }

  function mint(address to, uint256 amount) public override authorized {
    _mint(to, amount);
  }
}