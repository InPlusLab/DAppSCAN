// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAaveLendingPoolProvider {
  function getLendingPool() external view returns (address);
}
