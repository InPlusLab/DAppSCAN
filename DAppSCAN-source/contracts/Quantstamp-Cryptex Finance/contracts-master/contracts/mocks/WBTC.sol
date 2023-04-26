// SPDX-License-Identifier: MIT
/** @notice this contract is for tests only */

pragma solidity 0.7.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WBTC is ERC20 {
  constructor() ERC20("Mockup WBTC", "mWBTC") {
    _setupDecimals(8);
  }

  function mint(address _account, uint256 _amount) public {
    _mint(_account, _amount);
  }

  function burn(address _account, uint256 _amount) public {
    _burn(_account, _amount);
  }
}
