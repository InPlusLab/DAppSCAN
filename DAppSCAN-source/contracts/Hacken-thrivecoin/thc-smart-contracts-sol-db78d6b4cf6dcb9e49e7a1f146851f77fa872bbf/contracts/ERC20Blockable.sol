// SPDX-License-Identifier: MIT
// SWC-103-Floating Pragma: L3
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Extension of {ERC20} that adds capability for blocking accounts
 */
abstract contract ERC20Blockable is ERC20 {
  /**
   * @dev Events related to account blocking
   */
  event AccountBlocked(address indexed account, uint256 timestamp);
  event AccountUnblocked(address indexed account, uint256 timestamp);

  /**
   * @dev Mapping that tracks blocked accounts
   */
  mapping(address => bool) _blockedAccounts;

  /**
   * @dev Returns `true` if `account` has been blocked.
   */
  function isAccountBlocked(address account) public view returns (bool) {
    return _blockedAccounts[account];
  }

  /**
   * @dev Blocks the account, if account is already blocked action call
   * is reverted
   */
  function _blockAccount(address account) internal virtual {
    require(!isAccountBlocked(account), "ERC20Blockable: account is already blocked");

    _blockedAccounts[account] = true;
    emit AccountBlocked(account, block.timestamp);
  }

  /**
   * @dev Unblocks the account, if account is not blocked action call
   * is reverted
   */
  function _unblockAccount(address account) internal virtual {
    require(isAccountBlocked(account), "ERC20Blockable: account is not blocked");

    _blockedAccounts[account] = false;
    emit AccountUnblocked(account, block.timestamp);
  }

  /**
   * @dev See {ERC20-_beforeTokenTransfer}
   */
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override {
    require(!isAccountBlocked(from), "ERC20Blockable: sender account should be not be blocked");
    require(!isAccountBlocked(to), "ERC20Blockable: receiver account should be not be blocked");
    require(!isAccountBlocked(_msgSender()), "ERC20Blockable: caller account should be not be blocked");
    super._beforeTokenTransfer(from, to, amount);
  }
}
