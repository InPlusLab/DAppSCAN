// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IKeep3rJob {
  function keep3r() external view returns (address _keep3r);

  function keep3rProxyJob() external view returns (address _keep3rProxyJob);

  function maxGasPrice() external view returns (uint256 _maxGasPrice);

  function work(bytes calldata _workData) external;

  // use callStatic for the following functions:
  function workable() external returns (bool);

  function getWorkData() external returns (bytes memory _workData);
}
