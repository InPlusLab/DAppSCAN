// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import './interfaces/IStealthVault.sol';
import './interfaces/IStealthTx.sol';

/*
 * StealthTxAbstract
 */
abstract contract StealthTx is IStealthTx {
  address public override stealthVault;
  uint256 public override penalty = 1 ether;

  constructor(address _stealthVault) {
    _setStealthVault(_stealthVault);
  }

  modifier validateStealthTx(bytes32 _stealthHash) {
    // if not valid, do not revert execution. just return.
    if (!_validateStealthTx(_stealthHash)) return;
    _;
  }

  modifier validateStealthTxAndBlock(bytes32 _stealthHash, uint256 _blockNumber) {
    // if not valid, do not revert execution. just return.
    if (!_validateStealthTxAndBlock(_stealthHash, _blockNumber)) return;
    _;
  }

  function _validateStealthTx(bytes32 _stealthHash) internal returns (bool) {
    return IStealthVault(stealthVault).validateHash(msg.sender, _stealthHash, penalty);
  }

  function _validateStealthTxAndBlock(bytes32 _stealthHash, uint256 _blockNumber) internal returns (bool) {
    require(block.number == _blockNumber, 'ST: wrong block');
    return _validateStealthTx(_stealthHash);
  }

  function _setPenalty(uint256 _penalty) internal {
    require(_penalty > 0, 'ST: zero penalty');
    penalty = _penalty;
    emit PenaltySet(_penalty);
  }

  function _setStealthVault(address _stealthVault) internal {
    require(_stealthVault != address(0), 'ST: zero address');
    require(IStealthVault(_stealthVault).isStealthVault(), 'ST: not stealth vault');
    stealthVault = _stealthVault;
    emit StealthVaultSet(_stealthVault);
  }
}
