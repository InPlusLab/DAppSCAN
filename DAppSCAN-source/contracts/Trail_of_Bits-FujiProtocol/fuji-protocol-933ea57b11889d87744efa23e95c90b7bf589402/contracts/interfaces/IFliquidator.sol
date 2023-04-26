// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFliquidator {
  function executeFlashClose(
    address _userAddr,
    address _vault,
    uint256 _amount,
    uint256 _flashloanfee
  ) external payable;

  function executeFlashBatchLiquidation(
    address[] calldata _userAddrs,
    uint256[] calldata _usrsBals,
    address _liquidatorAddr,
    address _vault,
    uint256 _amount,
    uint256 _flashloanFee
  ) external payable;
}
