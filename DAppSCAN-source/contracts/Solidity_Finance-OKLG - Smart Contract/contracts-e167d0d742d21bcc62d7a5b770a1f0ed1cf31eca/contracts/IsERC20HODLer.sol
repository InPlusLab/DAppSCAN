// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import './interfaces/IConditional.sol';

contract IsERC20HODLer is IConditional, Ownable {
  address public tokenContract;
  uint256 public numSecondsForBooster = 60 * 60 * 24 * 7; // 7 days
  mapping(address => uint256) public userBalances;
  mapping(address => uint256) public userBalTimestamp;

  constructor(address _tokenContract) {
    tokenContract = _tokenContract;
  }

  function passesTest(address wallet) external view override returns (bool) {
    uint256 userBal = IERC20(tokenContract).balanceOf(wallet);
    return
      userBal > 0 &&
      userBalances[wallet] > 0 &&
      userBalTimestamp[wallet] > 0 &&
      userBal >= userBalances[wallet] &&
      block.timestamp > userBalTimestamp[wallet] + numSecondsForBooster;
  }

  function setBalanceAndTimestamp() external {
    userBalances[msg.sender] = IERC20(tokenContract).balanceOf(msg.sender);
    userBalTimestamp[msg.sender] = block.timestamp;
  }

  function setTokenAddress(address _tokenContract) external onlyOwner {
    tokenContract = _tokenContract;
  }

  function setNumSecondsForBooster(uint256 _seconds) external onlyOwner {
    numSecondsForBooster = _seconds;
  }
}
