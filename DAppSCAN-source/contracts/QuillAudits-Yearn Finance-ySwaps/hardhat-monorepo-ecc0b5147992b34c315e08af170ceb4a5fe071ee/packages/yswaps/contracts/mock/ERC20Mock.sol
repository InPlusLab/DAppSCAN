// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.6;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract ERC20Mock is ERC20 {
  uint8 private _decimals;

  constructor(
    string memory _name,
    string memory _symbol,
    uint8 __decimals,
    address _initialAccount,
    uint256 _initialBalance
  ) payable ERC20(_name, _symbol) {
    _decimals = __decimals;
    if (_initialBalance > 0) {
      _mint(_initialAccount, _initialBalance);
    }
  }

  function mint(address _account, uint256 _amount) external {
    _mint(_account, _amount);
  }

  function burn(address _account, uint256 _amount) external {
    _burn(_account, _amount);
  }

  function transferInternal(
    address _from,
    address _to,
    uint256 _value
  ) external {
    _transfer(_from, _to, _value);
  }

  function approveInternal(
    address _owner,
    address _spender,
    uint256 _value
  ) external {
    _approve(_owner, _spender, _value);
  }

  function decimals() public view virtual override returns (uint8) {
    return _decimals;
  }
}