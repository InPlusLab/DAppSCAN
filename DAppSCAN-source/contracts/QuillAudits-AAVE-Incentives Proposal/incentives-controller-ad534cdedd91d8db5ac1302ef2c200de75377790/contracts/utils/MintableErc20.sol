// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {ERC20} from '@aave/protocol-v2/contracts/dependencies/openzeppelin/contracts/ERC20.sol';

/**
 * @title ERC20Mintable
 * @dev ERC20 minting logic
 */
contract MintableErc20 is ERC20 {
  constructor(string memory name, string memory symbol) public ERC20(name, symbol) {}

  /**
   * @dev Function to mint tokens
   * @param value The amount of tokens to mint.
   * @return A boolean that indicates if the operation was successful.
   */
  function mint(uint256 value) public returns (bool) {
    _mint(msg.sender, value);
    return true;
  }

  /**
   * @dev implements a mock permit feature
   **/
  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    _approve(owner, spender, value);
  }
}
