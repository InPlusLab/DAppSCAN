// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import '../StealthTx.sol';

contract StealthTxMock is StealthTx {
  event Event();

  constructor(address _stealthVault) StealthTx(_stealthVault) { }

  function validateStealthTxModifier(bytes32 _stealthHash) external validateStealthTx(_stealthHash) {
    emit Event();
  }

  function validateStealthTxAndBlockModifier(bytes32 _stealthHash, uint256 _blockNumber) external validateStealthTxAndBlock(_stealthHash, _blockNumber) {
    emit Event();
  }

  function validateStealthTxFunction(bytes32 _stealthHash) external returns (bool) {
    return _validateStealthTx(_stealthHash);
  }

  function validateStealthTxAndBlockFunction(bytes32 _stealthHash, uint256 _blockNumber) external returns (bool) {
    return _validateStealthTxAndBlock(_stealthHash, _blockNumber);
  }

  function setStealthVault(address _stealthVault) external override {
    _setStealthVault(_stealthVault);
  }

  function setPenalty(uint256 _penalty) external override {
    _setPenalty(_penalty);
  }
}
