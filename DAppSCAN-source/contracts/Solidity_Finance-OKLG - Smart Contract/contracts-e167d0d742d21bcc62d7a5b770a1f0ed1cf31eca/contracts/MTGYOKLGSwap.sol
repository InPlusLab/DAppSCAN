// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';

/**
 * @title MTGYOKLGSwap
 * @dev Swap MTGY for OKLG on BSC
 */
contract MTGYOKLGSwap is Ownable {
  IERC20 private mtgy = IERC20(0x025c9f1146d4d94F8F369B9d98104300A3c8ca23);
  IERC20 private oklg = IERC20(0x55E8b37a3c43B049deDf56C77f462Db095108651);

  uint8 public mtgyOklgRatio = 120;

  function swap() external {
    uint256 mtgyBalance = mtgy.balanceOf(msg.sender);
    require(mtgyBalance > 0, 'must have a MTGY balance to swap for OKLG');

    uint256 oklgToTransfer = (mtgyBalance * mtgyOklgRatio) / 10**9; // MTGY has 18 decimals, OKLG has 9 decimals
    require(
      oklg.balanceOf(address(this)) >= oklgToTransfer,
      'not enough OKLG liquidity to execute swap'
    );

    mtgy.transferFrom(msg.sender, address(this), mtgyBalance);
    oklg.transfer(msg.sender, oklgToTransfer);
  }

  function changeRatio(uint8 _newRatio) external onlyOwner {
    mtgyOklgRatio = _newRatio;
  }

  function withdrawTokens(address _tokenAddy, uint256 _amount)
    external
    onlyOwner
  {
    IERC20 _token = IERC20(_tokenAddy);
    _amount = _amount > 0 ? _amount : _token.balanceOf(address(this));
    require(_amount > 0, 'make sure there is a balance available to withdraw');
    _token.transfer(owner(), _amount);
  }
}
