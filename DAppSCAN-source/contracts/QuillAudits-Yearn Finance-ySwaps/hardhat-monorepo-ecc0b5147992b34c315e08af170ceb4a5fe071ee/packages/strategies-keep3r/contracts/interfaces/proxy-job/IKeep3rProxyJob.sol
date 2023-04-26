// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import '@yearn/contract-utils/contracts/interfaces/keep3r/IKeep3r.sol';

interface IKeep3rProxyJob is IKeep3r {
  event Worked(address _job, address _keeper);

  // view
  function jobs() external view returns (address[] memory validJobs);

  // keeper
  function work(address _job, bytes calldata _workData) external;

  // use callStatic
  function workable(address _job) external returns (bool _workable);

  function isValidJob(address _job) external view returns (bool _valid);
}
