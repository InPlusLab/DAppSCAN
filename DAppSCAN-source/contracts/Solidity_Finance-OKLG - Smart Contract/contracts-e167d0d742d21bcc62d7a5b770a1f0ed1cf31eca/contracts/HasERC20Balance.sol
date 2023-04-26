// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import './interfaces/IConditional.sol';

contract HasERC20Balance is IConditional, Ownable {
  address public tokenContract;
  uint256 public minTokenBalance = 1;

  constructor(address _tokenContract) {
    tokenContract = _tokenContract;
  }

  function passesTest(address wallet) external view override returns (bool) {
    return IERC20(tokenContract).balanceOf(wallet) >= minTokenBalance;
  }

  function setTokenAddress(address _tokenContract) external onlyOwner {
    tokenContract = _tokenContract;
  }

  function setMinTokenBalance(uint256 _newMin) external onlyOwner {
    minTokenBalance = _newMin;
  }
}
