// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Extension of {ERC20} that adds a cap to the supply of tokens.
 * The cap is dynamic still but can only be decreased further
 */
abstract contract ERC20DynamicCap is ERC20 {
  /**
   * @dev Emitted when cap is updated/decreased
   */
  event CapUpdated(address indexed from, uint256 prevCap, uint256 newCap);

  uint256 private _cap = 2**256 - 1; // MAX_INT

  /**
   * @dev Sets the value of the `cap`. This value later can only be decreased.
   */
  constructor(uint256 cap_) {
    _updateCap(cap_);
  }

  /**
   * @dev Returns the cap on the token's total supply.
   */
  function cap() public view virtual returns (uint256) {
    return _cap;
  }

  /**
   * @dev Decreases total supply cap
   */
  function updateCap(uint256 cap_) public virtual {
    _updateCap(cap_);
  }

  /**
   * @dev Sets the value of the `cap`. This value can only be decreased
   * further, it can't be increased
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
   * @dev See {ERC20-_mint}.
   */
  function _mint(address account, uint256 amount) internal virtual override {
    require(totalSupply() + amount <= cap(), "ERC20DynamicCap: cap exceeded");
    super._mint(account, amount);
  }
}
