// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC721.sol';
import './interfaces/IConditional.sol';

contract HasERC721Balance is IConditional, Ownable {
  address public nftContract;
  uint256 public minTokenBalance = 1;

  constructor(address _nftContract) {
    nftContract = _nftContract;
  }

  function passesTest(address wallet) external view override returns (bool) {
    return IERC721(nftContract).balanceOf(wallet) >= minTokenBalance;
  }

  function setTokenAddress(address _nftContract) external onlyOwner {
    nftContract = _nftContract;
  }

  function setMinTokenBalance(uint256 _newMin) external onlyOwner {
    minTokenBalance = _newMin;
  }
}
