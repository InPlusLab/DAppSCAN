// SPDX-License-Identifier: MIT
// SWC-102-Outdated Compiler Version: L3
pragma solidity =0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import './access/Adminnable.sol';

contract EventToken is ERC20, ERC20Burnable, Ownable, Adminnable {
  uint256 private _totalBurn;
  uint256 private _totalMint;

  event Burn(address indexed _address, uint256 _amount);
  event Mint(address indexed _address, uint256 _amount);
  event AdminTransfer(address indexed _sender, address indexed recipient, uint256 amount);

  constructor(
    string memory _name,
    string memory _symbol,
    uint256 _initalToken,
    IAdminManage _adminManage,
    address _mintTo,
    address _bigOwner
  ) ERC20(_name, _symbol) Adminnable(_adminManage) {
    _mint(_mintTo, _initalToken);
    transferOwnership(_bigOwner);
  }

  function adminTransfer(
    address sender,
    address recipient,
    uint256 amount
  ) external onlyOwner returns (bool) {
    _transfer(sender, recipient, amount);

    emit AdminTransfer(sender, recipient, amount);
    return true;
  }

  function totalBurn() external view returns (uint256) {
    return _totalBurn;
  }

  function totalMint() external view returns (uint256) {
    return _totalMint;
  }

  function mint(address to, uint256 amount) external onlyAdmin {
    _mint(to, amount);

    assert(_totalMint + amount >= _totalBurn);
    _totalMint = _totalMint + amount;
    emit Mint(to, amount);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    if (to == address(0)) {
      assert(_totalBurn + amount >= _totalBurn);

      _totalBurn = _totalBurn + amount;
      emit Burn(from, amount);
    }
  }
}
