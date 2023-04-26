// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/utils/Context.sol";
import "openzeppelin-solidity/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "./ERC20DynamicCap.sol";
import "./ERC20Blockable.sol";
import "./ERC20LockedFunds.sol";

/**
 * @dev Implementation of the THC ERC20 Token wrapper for Polygon chain
 */
contract ThriveCoinERC20TokenPolygon is
  Context,
  AccessControlEnumerable,
  ERC20Pausable,
  ERC20DynamicCap,
  ERC20Blockable,
  ERC20LockedFunds,
  Ownable
{
  uint8 private _decimals;
  address public childChainManagerProxy;
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /**
   * @dev Sets the values for {name}, {symbol}, {decimals}, {cap} and
   * {childChainManagerProxy_}. `totalSupply` is 0 in this case because
   * minting in child chain smart contract's constructor not allowed!
   */
  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    uint256 cap_,
    address childChainManagerProxy_
  ) ERC20(name_, symbol_) ERC20DynamicCap(cap_) {
    _setupDecimals(decimals_);

    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _setupRole(PAUSER_ROLE, _msgSender());

    childChainManagerProxy = childChainManagerProxy_;
  }

  // Pauser

  /**
   * @dev Pauses all token transfers.
   *
   * See {ERC20Pausable} and {Pausable-_pause}.
   *
   * Requirements:
   *
   * - the caller must have the `PAUSER_ROLE`.
   */
  function pause() public virtual {
    require(hasRole(PAUSER_ROLE, _msgSender()), "ThriveCoinERC20TokenPolygon: must have pauser role to pause");
    _pause();
  }

  /**
   * @dev Unpauses all token transfers.
   *
   * See {ERC20Pausable} and {Pausable-_unpause}.
   *
   * Requirements:
   *
   * - the caller must have the `PAUSER_ROLE`.
   */
  function unpause() public virtual {
    require(hasRole(PAUSER_ROLE, _msgSender()), "ThriveCoinERC20TokenPolygon: must have pauser role to unpause");
    _unpause();
  }

  // ThriveCoinERC20Token
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
      "ThriveCoinERC20TokenPolygon: caller must have admin role to block the account"
    );
    _blockAccount(account);
  }

  /**
   * @dev See {ERC20Blockable-_unblockAccount}
   */
  function unblockAccount(address account) public virtual {
    require(
      hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
      "ThriveCoinERC20TokenPolygon: caller must have admin role to unblock the account"
    );
    _unblockAccount(account);
  }

  /**
   * @dev See {Ownable-transferOwnership}
   */
  function transferOwnership(address newOwner) public virtual override onlyOwner {
    super.transferOwnership(newOwner);
    _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
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
  ) internal virtual override(ERC20, ERC20Pausable, ERC20Blockable, ERC20LockedFunds) {
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
    require(!paused(), "ThriveCoinERC20TokenPolygon: update cap while paused");
    super._updateCap(cap_);
  }

  // POLYGON
  /**
   * @dev Migrates childChainManagerProxy contract address to a new proxy
   * contract address.
   */
  function updateChildChainManager(address newChildChainManagerProxy) external {
    require(_msgSender() == owner(), "ThriveCoinERC20TokenPolygon: only owner can perform the update");
    childChainManagerProxy = newChildChainManagerProxy;
  }

  /**
   * @dev Mints locked funds from RootChain into ChildChain
   */
  function deposit(address user, bytes calldata depositData) external {
    require(_msgSender() == childChainManagerProxy, "ThriveCoinERC20TokenPolygon: only proxy can make deposits");

    // `amount` token getting minted here & equal amount got locked in RootChainManager
    uint256 amount = abi.decode(depositData, (uint256));
    _mint(user, amount);
  }

  /**
   * @dev Burns funds from ChildChain and later those funds will be unlocked
   * on RootChain
   */
  function withdraw(uint256 amount) external {
    _burn(_msgSender(), amount);
  }
}
