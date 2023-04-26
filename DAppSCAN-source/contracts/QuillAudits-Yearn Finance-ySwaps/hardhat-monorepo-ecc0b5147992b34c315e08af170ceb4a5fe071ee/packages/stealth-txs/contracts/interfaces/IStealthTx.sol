// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IStealthTx {
  event StealthVaultSet(address _stealthVault);
  event PenaltySet(uint256 _penalty);
  event MigratedStealthVault(address _migratedTo);

  function stealthVault() external view returns (address);

  function penalty() external view returns (uint256);

  function setStealthVault(address _stealthVault) external;

  function setPenalty(uint256 _penalty) external;
}
