// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IBaseFee {
  // solhint-disable-next-line func-name-mixedcase
  function basefee_global() external view returns (uint256 _basefee);
}
