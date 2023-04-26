// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

/**
 * @author vigan.abd
 * @title ERC20 with adjustable cap
 *
 * @dev Extension of {ERC20} that adds a cap to the supply of tokens.
 * The cap is dynamic still but can only be decreased further!
 *
 * NOTE: extends openzeppelin v4.3.2 ERC20 contract:
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.2/contracts/token/ERC20/ERC20.sol
 */
abstract contract ERC20DynamicCap is ERC20 {
  /**
   * @dev Emitted when cap is updated/decreased
   *
   * @param from - Account that updated cap
   * @param prevCap - Previous cap
   * @param newCap - New cap
   */
  event CapUpdated(address indexed from, uint256 prevCap, uint256 newCap);

  uint256 private _cap = 2**256 - 1; // MAX_INT

  /**
   * @dev Sets the value of the `cap`. This value later can only be decreased.
   *
   * @param cap_ - Initial cap (max total supply)
   */
  constructor(uint256 cap_) {
    _updateCap(cap_);
  }

  /**
   * @dev Returns the cap on the token's total supply (max total supply).
   *
   * @return uint256
   */
  function cap() public view virtual returns (uint256) {
    return _cap;
  }

  /**
   * @dev Sets the value of the `cap`. This value can only be decreased
   * further, it can't be increased
   *
   * @param cap_ - New cap, should be lower or equal to previous cap
   */
  function _updateCap(uint256 cap_) internal virtual {
    require(cap_ > 0, "ERC20DynamicCap: cap cannot be 0");
    require(cap_ < _cap, "ERC20DynamicCap: cap can only be decreased");
    require(cap_ >= totalSupply(), "ERC20DynamicCap: cap cannot be less than total supply");
    uint256 prevCap = _cap;
    _cap = cap_;
    emit CapUpdated(_msgSender(), prevCap, cap_);
  }

  /**
   * @dev See {ERC20-_mint}. Adds restriction on minting functionality by
   * disallowing total supply to exceed cap
   *
   * @param account - Accounts where the minted funds will be sent
   * @param amount - Amount that will be minted
   */
  function _mint(address account, uint256 amount) internal virtual override {
    require(totalSupply() + amount <= cap(), "ERC20DynamicCap: cap exceeded");
    super._mint(account, amount);
  }
}
