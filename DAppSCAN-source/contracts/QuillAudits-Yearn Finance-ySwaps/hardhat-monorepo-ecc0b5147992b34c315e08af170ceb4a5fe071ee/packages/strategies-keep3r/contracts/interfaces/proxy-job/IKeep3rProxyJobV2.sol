// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import '@yearn/contract-utils/contracts/interfaces/keep3r/IKeep3r.sol';

interface IKeep3rProxyJobV2 is IKeep3r {
  event AddValidJob(address _job, uint256 _maxCredits);
  event RemoveValidJob(address _job);
  event SetJobMaxCredits(address _job, uint256 _maxCredits);
  event SetJobRewardMultiplier(address _job, uint256 _rewardMultiplier);
  event Worked(address _job, address _keeper, uint256 _credits, bool _workForTokens);

  // setters
  function addValidJob(
    address _job,
    uint256 _maxCredits,
    uint256 _rewardMultiplier
  ) external;

  function removeValidJob(address _job) external;

  function setJobMaxCredits(address _job, uint256 _maxCredits) external;

  function setJobRewardMultiplier(address _job, uint256 _rewardMultiplier) external;

  // view
  function jobs() external view returns (address[] memory validJobs);

  function usedCredits(address _job) external view returns (uint256 _usedCredits);

  function maxCredits(address _job) external view returns (uint256 _maxCredits);

  function rewardMultiplier(address _job) external view returns (uint256 _rewardMultiplier);

  // keeper
  function work(address _job, bytes calldata _workData) external returns (uint256 _credits);

  function workForBond(address _job, bytes calldata _workData) external returns (uint256 _credits);

  function workForTokens(address _job, bytes calldata _workData) external returns (uint256 _credits);

  // use callStatic
  function workable(address _job) external returns (bool _workable);

  function isValidJob(address _job) external view returns (bool _valid);
}
