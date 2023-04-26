// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@yearn/contract-utils/contracts/utils/CollectableDust.sol';
import '@yearn/contract-utils/contracts/utils/Governable.sol';
import '@openzeppelin/contracts/utils/Address.sol';

import './interfaces/IStealthRelayer.sol';
import './StealthTx.sol';

/*
 * StealthRelayer
 */
contract StealthRelayer is Governable, CollectableDust, StealthTx, IStealthRelayer {
  using Address for address;
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _jobs;

  bool public override forceBlockProtection;
  address public override caller;

  constructor(address _stealthVault) Governable(msg.sender) StealthTx(_stealthVault) {}

  modifier onlyValidJob(address _job) {
    require(_jobs.contains(_job), 'SR: invalid job');
    _;
  }

  modifier setsCaller() {
    caller = msg.sender;
    _;
    caller = address(0);
  }

  function execute(
    address _job,
    bytes memory _callData,
    bytes32 _stealthHash,
    uint256 _blockNumber
  )
    external
    payable
    override
    onlyValidJob(_job)
    validateStealthTxAndBlock(_stealthHash, _blockNumber)
    setsCaller
    returns (bytes memory _returnData)
  {
    return _callWithValue(_job, _callData, msg.value);
  }

  function executeAndPay(
    address _job,
    bytes memory _callData,
    bytes32 _stealthHash,
    uint256 _blockNumber,
    uint256 _payment
  )
    external
    payable
    override
    onlyValidJob(_job)
    validateStealthTxAndBlock(_stealthHash, _blockNumber)
    setsCaller
    returns (bytes memory _returnData)
  {
    _returnData = _callWithValue(_job, _callData, msg.value - _payment);
    block.coinbase.transfer(_payment);
  }

  function executeWithoutBlockProtection(
    address _job,
    bytes memory _callData,
    bytes32 _stealthHash
  ) external payable override onlyValidJob(_job) validateStealthTx(_stealthHash) setsCaller returns (bytes memory _returnData) {
    require(!forceBlockProtection, 'SR: block protection required');
    return _callWithValue(_job, _callData, msg.value);
  }

  function executeWithoutBlockProtectionAndPay(
    address _job,
    bytes memory _callData,
    bytes32 _stealthHash,
    uint256 _payment
  ) external payable override onlyValidJob(_job) validateStealthTx(_stealthHash) setsCaller returns (bytes memory _returnData) {
    require(!forceBlockProtection, 'SR: block protection required');
    _returnData = _callWithValue(_job, _callData, msg.value - _payment);
    block.coinbase.transfer(_payment);
  }

  function _callWithValue(
    address _job,
    bytes memory _callData,
    uint256 _value
  ) internal returns (bytes memory _returnData) {
    return _job.functionCallWithValue(_callData, _value, 'SR: call reverted');
  }

  function setForceBlockProtection(bool _forceBlockProtection) external override onlyGovernor {
    forceBlockProtection = _forceBlockProtection;
  }

  function jobs() external view override returns (address[] memory _jobsList) {
    _jobsList = new address[](_jobs.length());
    for (uint256 i; i < _jobs.length(); i++) {
      _jobsList[i] = _jobs.at(i);
    }
  }

  // Setup trusted contracts to call (jobs)
  function addJobs(address[] calldata _jobsList) external override onlyGovernor {
    for (uint256 i = 0; i < _jobsList.length; i++) {
      _addJob(_jobsList[i]);
    }
  }

  function addJob(address _job) external override onlyGovernor {
    _addJob(_job);
  }

  function _addJob(address _job) internal {
    require(_jobs.add(_job), 'SR: job already added');
  }

  function removeJobs(address[] calldata _jobsList) external override onlyGovernor {
    for (uint256 i = 0; i < _jobsList.length; i++) {
      _removeJob(_jobsList[i]);
    }
  }

  function removeJob(address _job) external override onlyGovernor {
    _removeJob(_job);
  }

  function _removeJob(address _job) internal {
    require(_jobs.remove(_job), 'SR: job not found');
  }

  // StealthTx: restricted-access
  function setPenalty(uint256 _penalty) external override onlyGovernor {
    _setPenalty(_penalty);
  }

  function setStealthVault(address _stealthVault) external override onlyGovernor {
    _setStealthVault(_stealthVault);
  }

  // Governable: restricted-access
  function setPendingGovernor(address _pendingGovernor) external override onlyGovernor {
    _setPendingGovernor(_pendingGovernor);
  }

  function acceptGovernor() external override onlyPendingGovernor {
    _acceptGovernor();
  }

  // Collectable Dust: restricted-access
  function sendDust(
    address _to,
    address _token,
    uint256 _amount
  ) external override onlyGovernor {
    _sendDust(_to, _token, _amount);
  }
}
