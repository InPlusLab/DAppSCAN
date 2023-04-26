// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "./ERC20DynamicCap.sol";
import "./ERC20Blockable.sol";
import "./ERC20LockedFunds.sol";

/**
 * @dev Implementation of the THC ERC20 Token.
 *
 * THRIVE is a dynamic supply cross chain ERC20 token that supports burning and
 * minting. The token is capped where `cap` is dynamic, but can only be
 * decreased after the initial value. The decrease of `cap` happens when
 * additional blockchains are added. The idea is to divide every blockchain
 * to keep nearly equal `cap`, so e.g. when a new blockchain is supported
 * all existing blockchains decrease their `cap`.
 *
 * Token cross chain swapping is supported through minting and burning
 * where a separate smart contract also owned by THC owner will operate on each
 * chain and will handle requests. The steps of swapping are:
 * - `address` calls approve(`swap_contract_chain_1`, `swap_amount`)
 * - `swap_contract_chain_1` calls burnFrom(`address`, `swap_amount`)
 * - `swap_contract_chain_2` calls mint(`address`, `swap_amount`)
 * NOTE: If an address beside `swap_contract_chain_1` calls burn action
 * the funds will be lost forever and are not recoverable, this will cause to
 * decrease total supply additionally!
 *
 * Another key feature of THRIVE is ability to lock funds to be spend only by
 * specific accounts. This is achieved through `lockAmount` and `unlockAmount`
 * actions, where the first one is called by balance owner and second by spender.
 *
 * Key features:
 * - burn
 * - mint
 * - capped, dynamic decreasing only
 * - pausable
 * - blocking/unblocking accounts
 * - role management
 * - locking/unlocking funds
 */
contract ThriveCoinERC20Token is ERC20PresetMinterPauser, ERC20DynamicCap, ERC20Blockable, ERC20LockedFunds, Ownable {
  uint8 private _decimals;

  /**
   * @dev Sets the values for {name}, {symbol}, {decimals}, {totalSupply} and
   * {cap}.
   *
   * All of these values beside {cap} are immutable: they can only be set
   * once during construction. {cap} param is only decreasable and is expected
   * to decrease when additional blockchains are added.
   *
   */
  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    uint256 totalSupply_,
    uint256 cap_
  ) ERC20PresetMinterPauser(name_, symbol_) ERC20DynamicCap(cap_) {
    _setupDecimals(decimals_);
    _mint(owner(), totalSupply_);
  }

  /**
   * @dev Returns the number of decimals used to get its user representation.
   * For example, if `decimals` equals `2`, a balance of `505` tokens should
   * be displayed to a user as `5.05` (`505 / 10 ** 2`).
   *
   * NOTE: This information is only used for _display_ purposes: it in
   * no way affects any of the arithmetic of the contract, including
   * {IERC20-balanceOf} and {IERC20-transfer}.
   */
  function decimals() public view virtual override returns (uint8) {
    return _decimals;
  }

  /**
   * @dev See {ERC20DynamicCap-updateCap}
   */
  function updateCap(uint256 cap_) public virtual override onlyOwner {
    super.updateCap(cap_);
  }

  /**
   * @dev See {ERC20Blockable-_blockAccount}
   */
  function blockAccount(address account) public virtual {
    require(
      hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
      "ThriveCoinERC20Token: caller must have admin role to block the account"
    );
    _blockAccount(account);
  }

  /**
   * @dev See {ERC20Blockable-_unblockAccount}
   */
  function unblockAccount(address account) public virtual {
    require(
      hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
      "ThriveCoinERC20Token: caller must have admin role to unblock the account"
    );
    _unblockAccount(account);
  }

  /**
   * @dev See {Ownable-transferOwnership}
   */
  function transferOwnership(address newOwner) public virtual override onlyOwner {
    super.transferOwnership(newOwner);
    _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
    _setupRole(MINTER_ROLE, newOwner);
    _setupRole(PAUSER_ROLE, newOwner);
  }

  /**
   * @dev Sets the value of `_decimals` field
   */
  function _setupDecimals(uint8 decimals_) internal virtual {
    _decimals = decimals_;
  }

  /**
   * @dev See {ERC20-_beforeTokenTransfer}.
   */
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override(ERC20, ERC20PresetMinterPauser, ERC20Blockable, ERC20LockedFunds) {
    super._beforeTokenTransfer(from, to, amount);
  }

  /**
   * @dev See {ERC20DynamicCap-_mint}.
   */
  function _mint(address account, uint256 amount) internal virtual override(ERC20, ERC20DynamicCap) {
    ERC20DynamicCap._mint(account, amount);
  }

  /**
   * @dev See {ERC20DynamicCap-_updateCap}
   */
  function _updateCap(uint256 cap_) internal virtual override {
    require(!paused(), "ThriveCoinERC20Token: update cap while paused");
    super._updateCap(cap_);
  }
}
