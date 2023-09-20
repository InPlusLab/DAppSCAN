// SPDX-License-Identifier: MIT
// SWC-103-Floating Pragma: L3
pragma solidity ^0.8.9;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

// Curate + Pellar 2022

contract Curate is Ownable, ERC20Burnable {
  uint256 public basisPointsRate;
  uint256 public maximumFee;
  address public masterAccount;

  constructor() ERC20("Curate", "XCUR") {
    _mint(0x34ac8D10152c6659b8e8102922EFEdD1e305D10A, 10000000 * (10 ** decimals()));
    setParams(0, 0, msg.sender);
  }

  /** View */
  function decimals() public view virtual override returns (uint8) {
    return 8;
  }

  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    if (basisPointsRate == 0) {
      return super.transfer(to, amount);
    }
    address owner = _msgSender();
    (uint256 fee, uint256 sendAmount) = computeFee(amount);
    _transfer(owner, masterAccount, fee);
    _transfer(owner, to, sendAmount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
    if (basisPointsRate == 0) {
      return super.transferFrom(from, to, amount);
    }
    address spender = _msgSender();
    _spendAllowance(from, spender, amount);
    (uint256 fee, uint256 sendAmount) = computeFee(amount);
    _transfer(from, masterAccount, fee);
    _transfer(from, to, sendAmount);
    return true;
  }

  function computeFee(uint256 _amount) internal view returns (uint256 fee, uint256 sendAmount) {
    fee = _amount * basisPointsRate / 10000;
    if (fee > maximumFee) {
      fee = maximumFee;
    }
    require(_amount > fee, "Insufficient amount");
    sendAmount = _amount - fee;
  }

  /** Admin */
  function mint(uint256 _amount) external onlyOwner {
    _mint(msg.sender, _amount);
  }

  function setParams(uint256 _newBasisPoints, uint256 _newMaxFee, address _masterAccount) public onlyOwner {
    basisPointsRate = _newBasisPoints;
    maximumFee = _newMaxFee * (10 ** decimals());
    masterAccount = _masterAccount;
  }

  function withdraw() public onlyOwner {
    uint256 balance = address(this).balance;
    payable(msg.sender).transfer(balance);
  }
}