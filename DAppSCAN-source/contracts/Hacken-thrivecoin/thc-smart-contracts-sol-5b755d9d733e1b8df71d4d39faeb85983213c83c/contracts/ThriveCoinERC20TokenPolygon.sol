// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/utils/Context.sol";
import "openzeppelin-solidity/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "./ERC20DynamicCap.sol";
import "./ERC20Blockable.sol";
import "./ERC20LockedFunds.sol";

/**
 * @author vigan.abd
 * @title ThriveCoin L2 ERC20 Token
 *
 * @dev Implementation of the THRIVE ERC20 Token wrapper for Polygon chain.
 * The key difference from L1 implementation is that Polygon implementation is 
 * Non Polygon-Mintable. So polygon implementation does not support `mint`
 * action and total supply by default is 0 since funds are supposed to be
 * moved later from L1 chain.
 
 * Additionally in difference from L1 chain, L2 implementation supports
 * `deposit`, `withdraw` and `updateChildChainManager` actions based on
 * recommendation from polygon docs
 * (https://docs.polygon.technology/docs/develop/ethereum-polygon/pos/mapping-assets#custom-child-token).
 * 
 * The rest of implementation is same as L1 contract!
 *
 * NOTE: extends openzeppelin v4.3.2 contracts:
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.2/contracts/utils/Context.sol
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.2/contracts/access/AccessControlEnumerable.sol
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.2/contracts/token/ERC20/extensions/ERC20Pausable.sol
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.2/contracts/access/Ownable.sol
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
  /**
   * @dev Denomination of token
   */
  uint8 private _decimals;

  /**
   * @dev Proxy chain manager contract address
   */
  address public childChainManagerProxy;

  /**
   * @dev Pauser role hash
   */
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /**
   * @dev Sets the values for {name}, {symbol}, {decimals}, {cap} and
   * {childChainManagerProxy_}. `totalSupply` is 0 in this case because
   * minting in child chain smart contract's constructor not allowed!
   *
   * @param name_ - Name of the token that complies with IERC20 interface
   * @param symbol_ - Symbol of the token that complies with IERC20 interface
   * @param decimals_ - Denomination of the token that complies with IERC20 interface
   * @param cap_ - Token supply max cap
   * @param childChainManagerProxy_ - Proxy chain manager contract address
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
  function pause() external virtual {
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
  function unpause() external virtual {
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
   *
   * @return uint8
   */
  function decimals() public view virtual override returns (uint8) {
    return _decimals;
  }

  /**
   * @dev See {ERC20DynamicCap-updateCap}. Adds only owner restriction to
   * updateCap action.
   *
   * @param cap_ - New cap, should be lower or equal to previous cap
   */
  function updateCap(uint256 cap_) external virtual onlyOwner {
    _updateCap(cap_);
  }

  /**
   * @dev See {ERC20Blockable-_blockAccount}. Adds admin only restriction to
   * blockAccount action
   *
   * @param account - Account that will be blocked
   */
  function blockAccount(address account) external virtual {
    require(
      hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
      "ThriveCoinERC20TokenPolygon: caller must have admin role to block the account"
    );
    _blockAccount(account);
  }

  /**
   * @dev See {ERC20Blockable-_unblockAccount}. Adds admin only restriction to
   * unblockAccount action
   *
   * @param account - Account that will be unblocked
   */
  function unblockAccount(address account) external virtual {
    require(
      hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
      "ThriveCoinERC20TokenPolygon: caller must have admin role to unblock the account"
    );
    _unblockAccount(account);
  }

  /**
   * @dev See {Ownable-transferOwnership}. Overrides action by adding also all
   * roles to new owner
   *
   * @param newOwner - The new owner of smart contract
   */
  function transferOwnership(address newOwner) public virtual override onlyOwner {
    address oldOwner = owner();

    super.transferOwnership(newOwner);
    _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
    _setupRole(PAUSER_ROLE, newOwner);

    renounceRole(DEFAULT_ADMIN_ROLE, oldOwner);
    renounceRole(PAUSER_ROLE, oldOwner);
  }

  /**
   * @dev Sets the value of `_decimals` field
   *
   * @param decimals_ - Denomination of the token that complies with IERC20 interface
   */
  function _setupDecimals(uint8 decimals_) internal virtual {
    _decimals = decimals_;
  }

  /**
   * @dev See {ERC20-_beforeTokenTransfer}. Adjust order of calls for extended
   * parent contracts.
   *
   * @param from - Account from where the funds will be sent
   * @param to - Account that will receive funds
   * @param amount - The amount that will be sent
   */
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override(ERC20, ERC20Pausable, ERC20Blockable, ERC20LockedFunds) {
    super._beforeTokenTransfer(from, to, amount);
  }

  /**
   * @dev See {ERC20DynamicCap-_mint}. Adjust order of calls for extended
   * parent contracts.
   *
   * @param account - Accounts where the minted funds will be sent
   * @param amount - Amount that will be minted
   */
  function _mint(address account, uint256 amount) internal virtual override(ERC20, ERC20DynamicCap) {
    ERC20DynamicCap._mint(account, amount);
  }

  /**
   * @dev See {ERC20DynamicCap-_updateCap}. Adds check for paused state to
   * _updateCap method.
   *
   * @param cap_ - New cap, should be lower or equal to previous cap
   */
  function _updateCap(uint256 cap_) internal virtual override {
    require(!paused(), "ThriveCoinERC20TokenPolygon: update cap while paused");
    super._updateCap(cap_);
  }

  // POLYGON
  /**
   * @dev Migrates childChainManagerProxy contract address to a new proxy
   * contract address.
   *
   * @param newChildChainManagerProxy - the new address for proxy chain manager
   */
  function updateChildChainManager(address newChildChainManagerProxy) external {
    require(_msgSender() == owner(), "ThriveCoinERC20TokenPolygon: only owner can perform the update");
    childChainManagerProxy = newChildChainManagerProxy;
  }

  /**
   * @dev Mints locked funds from RootChain into ChildChain
   *
   * @param user - Accounts where the minted funds will be sent
   * @param depositData - ABI encoded amount that will be minted
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
   *
   * @param amount - Amount that will be burned
   */
  function withdraw(uint256 amount) external {
    _burn(_msgSender(), amount);
  }
}
