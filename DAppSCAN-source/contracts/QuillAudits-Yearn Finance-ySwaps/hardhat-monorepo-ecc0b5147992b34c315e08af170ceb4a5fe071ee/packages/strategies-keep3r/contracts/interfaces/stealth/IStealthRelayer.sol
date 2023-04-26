// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import './IStealthTx.sol';

interface IStealthRelayer is IStealthTx {
  function caller() external view returns (address _caller);

  function forceBlockProtection() external view returns (bool _forceBlockProtection);

  function jobs() external view returns (address[] memory _jobsList);

  function setForceBlockProtection(bool _forceBlockProtection) external;

  function addJobs(address[] calldata _jobsList) external;

  function addJob(address _job) external;

  function removeJobs(address[] calldata _jobsList) external;

  function removeJob(address _job) external;

  function execute(
    address _address,
    bytes memory _callData,
    bytes32 _stealthHash,
    uint256 _blockNumber
  ) external payable returns (bytes memory _returnData);

  function executeAndPay(
    address _address,
    bytes memory _callData,
    bytes32 _stealthHash,
    uint256 _blockNumber,
    uint256 _payment
  ) external payable returns (bytes memory _returnData);

  function executeWithoutBlockProtection(
    address _address,
    bytes memory _callData,
    bytes32 _stealthHash
  ) external payable returns (bytes memory _returnData);

  function executeWithoutBlockProtectionAndPay(
    address _job,
    bytes memory _callData,
    bytes32 _stealthHash,
    uint256 _payment
  ) external payable returns (bytes memory _returnData);
}
