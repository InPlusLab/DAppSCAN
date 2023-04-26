// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

/**
 * @author vigan.abd
 * @title ERC20 with blocking capability
 *
 * @dev Extension of {ERC20} that adds capability for blocking/unblocking
 * accounts. Blocked accounts can't participate in transfers!
 *
 * NOTE: extends openzeppelin v4.3.2 ERC20 contract:
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.2/contracts/token/ERC20/ERC20.sol
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
   *
   * @param account - Account that will be checked
   * @return bool
   */
  function isAccountBlocked(address account) public view returns (bool) {
    return _blockedAccounts[account];
  }

  /**
   * @dev Blocks the account, if account is already blocked action call
   * is reverted
   *
   * @param account - Account that will be blocked
   */
  function _blockAccount(address account) internal virtual {
    require(!isAccountBlocked(account), "ERC20Blockable: account is already blocked");

    _blockedAccounts[account] = true;
    emit AccountBlocked(account, block.timestamp);
  }

  /**
   * @dev Unblocks the account, if account is not blocked action call
   * is reverted
   *
   * @param account - Account that will be unblocked
   */
  function _unblockAccount(address account) internal virtual {
    require(isAccountBlocked(account), "ERC20Blockable: account is not blocked");

    _blockedAccounts[account] = false;
    emit AccountUnblocked(account, block.timestamp);
  }

  /**
   * @dev See {ERC20-_beforeTokenTransfer}. Overrides _beforeTokenTransfer by
   * adding checks to reject transaction if at least one of source, dest or
   * caller is blocked.
   *
   * @param from - Account from where the funds will be sent
   * @param to - Account that will receive funds
   * @param amount - The amount that will be sent
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
