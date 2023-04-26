// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IvestingMinimal {

  function initialize (
    address _token,
    address _owner,
    uint256 _startInDays,
    uint256 _durationInDays,
    uint256 _cliffInTenThousands,
    uint256 _cliffDelayInDays,
    uint exp
  ) external;
}