// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

/**
 * @author vigan.abd
 * @title ERC20 with fund locking capability
 *
 * @dev Extension of {ERC20} that adds ability to lock funds to be spent only
 * by specific account
 *
 * NOTE: extends openzeppelin v4.3.2 ERC20 contract:
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.2/contracts/token/ERC20/ERC20.sol
 */
abstract contract ERC20LockedFunds is ERC20 {
  /**
   * @dev Emitted when funds of `owner` are locked to be spent only by `spender`.
   * `amount` is the additional locked amount!
   */
  event LockedFunds(address indexed owner, address indexed spender, uint256 amount);

  /**
   * @dev Emitted when funds of `owner` are unlocked from being spent only
   * by `spender`. `amount` is the subtracted from total locked amount!
   */
  event UnlockedFunds(address indexed owner, address indexed spender, uint256 amount);

  /**
   * @dev Emitted when `spender` spends locked funds of `owner`.
   * `amount` is spent amount.
   */
  event ClaimedLockedFunds(address indexed owner, address indexed spender, uint256 amount);

  mapping(address => uint256) private _lockedBalances;

  mapping(address => mapping(address => uint256)) private _lockedAccountBalanceMap;

  /**
   * @dev Returns the amount of locked tokens by `account`.
   *
   * @param account - Account whose locked balance will be checked
   */
  function lockedBalanceOf(address account) public view virtual returns (uint256) {
    return _lockedBalances[account];
  }

  /**
   * @dev Returns the remaining number of locked tokens that `spender` will be
   * allowed to spend on behalf of `owner`.
   *
   * @param owner - Account from where the funds are locked
   * @param spender - Account who locked the funds for spending
   */
  function lockedBalancePerAccount(address owner, address spender) public view virtual returns (uint256) {
    return _lockedAccountBalanceMap[owner][spender];
  }

  /**
   * @dev Locks the `amount` to be sent only to `spender` over the caller's
   * tokens. This `amount` does not override previous amount, it adds on top of
   * it. The locking guarantees that owner of funds can send the amount in
   * any time in future to the spender and cannot send this amount to some other
   * account.
   *
   * This action is different from approve function which gives allowance to
   * spend funds. This one just ensures that funds can't be sent somewhere else
   * but does not allow the spender to receive them by himself, these funds
   * still will be sent only by owner!
   *
   * Emits a {LockedFunds} event.
   *
   * @param owner - Account from where the funds are locked
   * @param spender - Account to whom funds will be locked for sending later
   * @param amount - The amount that will be locked
   */
  function lockAmount(
    address owner,
    address spender,
    uint256 amount
  ) external virtual {
    require(owner == _msgSender(), "ERC20LockedFunds: can lock only own funds");
    _lockAmount(owner, spender, amount);
  }

  /**
   * @dev Locks the `amount` to be spent by `spender`.
   * This `amount` does not override previous amount, it adds on top of it.
   *
   * This action ensures that allowed spender can fully spend the allowed funds
   * and that the owner cannot use these funds to send them somewhere else.
   *
   * Emits a {LockedFunds} event.
   *
   * @param owner - Account from where the funds are locked
   * @param spender - Account who locked the funds for spending
   * @param amount - The amount that will be locked
   */
  function lockAmountFrom(
    address owner,
    address spender,
    uint256 amount
  ) external virtual {
    require(spender == _msgSender(), "ERC20LockedFunds: only spender can request lock");
    require(
      allowance(owner, spender) >= amount + _lockedAccountBalanceMap[owner][spender],
      "ERC20LockedFunds: lock amount exceeds allowance"
    );
    _lockAmount(owner, spender, amount);
  }

  /**
   * @dev Unlocks the `amount` from being sent only to `caller` over the
   * `owner` balance.
   * This `amount` does not override previous locked balance, it reduces it.
   *
   * Emits a {UnlockedFunds} event.
   *
   * @param owner - Account from where the funds are locked
   * @param spender - Account to whom funds were locked
   * @param amount - The amount that will be unlocked
   */
  function unlockAmount(
    address owner,
    address spender,
    uint256 amount
  ) external virtual {
    require(spender == _msgSender(), "ERC20LockedFunds: only spender can unlock funds");
    _unlockAmount(owner, spender, amount);
  }

  /**
   * @dev Locks the `amount` to sent only to `spender` over the `owner` balance.
   * This `amount` does not override previous locked balance, it adds on top of it.
   *
   * Emits a {LockedFunds} event.
   *
   * @param owner - Account from where the funds are locked
   * @param spender - Account to whom funds will be locked for sending later
   * @param amount - The amount that will be locked
   */
  function _lockAmount(
    address owner,
    address spender,
    uint256 amount
  ) internal virtual {
    require(owner != address(0), "ERC20LockedFunds: lock from the zero address");
    require(spender != address(0), "ERC20LockedFunds: lock to the zero address");
    require(amount > 0, "ERC20LockedFunds: amount to be locked should be greater than zero");
    require(
      balanceOf(owner) >= amount + _lockedBalances[owner],
      "ERC20LockedFunds: amount greater than total lockable balance"
    );

    _lockedBalances[owner] += amount;
    _lockedAccountBalanceMap[owner][spender] += amount;

    emit LockedFunds(owner, spender, amount);
  }

  /**
   * @dev Unlocks the `amount` from being sent only to `spender` over the
   * `owner` balance.
   * This `amount` does not override previous locked balance, it reduces it.
   *
   * Emits a {UnlockedFunds} event.
   *
   * @param owner - Account from where the funds are locked
   * @param spender - Account to whom funds were locked
   * @param amount - The amount that will be unlocked
   */
  function _unlockAmount(
    address owner,
    address spender,
    uint256 amount
  ) internal virtual {
    require(owner != address(0), "ERC20LockedFunds: unlock from the zero address");
    require(spender != address(0), "ERC20LockedFunds: unlock to the zero address");
    require(amount > 0, "ERC20LockedFunds: amount to be unlocked should be greater than zero");

    require(_lockedBalances[owner] >= amount, "ERC20LockedFunds: unlock amount exceeds locked total balance");
    require(
      _lockedAccountBalanceMap[owner][spender] >= amount,
      "ERC20LockedFunds: unlock amount exceeds locked spender balance"
    );

    _lockedBalances[owner] -= amount;
    _lockedAccountBalanceMap[owner][spender] -= amount;

    emit UnlockedFunds(owner, spender, amount);
  }

  /**
   * @dev See {ERC20-_beforeTokenTransfer}. Overrides _beforeTokenTransfer by
   * adding checks for locked balances.
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
    super._beforeTokenTransfer(from, to, amount);

    if (from == address(0)) {
      // skip minting
      return;
    }

    address caller = _msgSender();
    address spender = from == caller ? to : caller; // from == caller -> transfer, otherwise transferFrom
    uint256 fromBalance = balanceOf(from);
    uint256 totalLockedBalance = _lockedBalances[from];
    uint256 lockedBySpender = _lockedAccountBalanceMap[from][spender];

    require(
      fromBalance + lockedBySpender - totalLockedBalance >= amount,
      "ERC20LockedFunds: amount exceeds balance allowed to be spent"
    );

    if (lockedBySpender > 0) {
      uint256 reducedAmount = lockedBySpender >= amount ? amount : lockedBySpender;
      _lockedAccountBalanceMap[from][from == caller ? to : caller] -= reducedAmount;
      _lockedBalances[from] -= reducedAmount;

      emit ClaimedLockedFunds(from, spender, reducedAmount);
    }
  }
}
