// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../interfaces/IConditional.sol';

contract OKLApeNewBuyerFeeExclusion is IConditional, Ownable {
  address public oklg;
  address public oklApe;
  uint256 public maxOKLGBalance = 10000 * 10**9;
  uint256 public minNFTBalance = 1;

  constructor(address _oklg, address _oklApe) {
    oklg = _oklg;
    oklApe = _oklApe;
  }

  function passesTest(address wallet) external view override returns (bool) {
    return
      wallet == address(0)
        ? false
        : IERC20(oklg).balanceOf(wallet) <= maxOKLGBalance &&
          IERC721(oklApe).balanceOf(wallet) >= minNFTBalance;
  }

  function setOKLGAddress(address _oklg) external onlyOwner {
    oklg = _oklg;
  }

  function setNFTAddress(address _oklApe) external onlyOwner {
    oklApe = _oklApe;
  }

  function setMaxOKLGBalance(uint256 _newMax) external onlyOwner {
    maxOKLGBalance = _newMax;
  }

  function setMinNFTBalance(uint256 _newMin) external onlyOwner {
    minNFTBalance = _newMin;
  }
}
