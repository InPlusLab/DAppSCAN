// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IERC20Detailed is IERC20Upgradeable {
  function name() external view returns(string memory);
  function decimals() external view returns(uint256);
}
