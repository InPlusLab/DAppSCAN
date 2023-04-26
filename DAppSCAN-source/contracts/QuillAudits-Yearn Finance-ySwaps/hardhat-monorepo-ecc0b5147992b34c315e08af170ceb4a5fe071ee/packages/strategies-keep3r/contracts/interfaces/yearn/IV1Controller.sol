// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IV1Controller {
  function stretegies(address _want) external view returns (address _strategy);

  function vaults(address _want) external view returns (address _vault);
}
