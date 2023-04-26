// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@yearn/contract-utils/contracts/abstract/MachineryReady.sol';
import '@yearn/contract-utils/contracts/keep3r/Keep3rAbstract.sol';
import '@yearn/contract-utils/contracts/interfaces/keep3r/IKeep3rV1.sol';

import '../interfaces/proxy-job/IKeep3rProxyJobV2.sol';
import '../interfaces/proxy-job/IKeep3rJob.sol';

contract Keep3rProxyJobV2 is MachineryReady, Keep3r, IKeep3rProxyJobV2 {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _validJobs;

  uint256 public constant PRECISION = 1_000;
  uint256 public constant MAX_REWARD_MULTIPLIER = 1 * PRECISION; // 1x max reward multiplier

  mapping(address => uint256) public override usedCredits;
  mapping(address => uint256) public override maxCredits;
  mapping(address => uint256) public override rewardMultiplier;

  constructor(
    address _mechanicsRegistry,
    address _keep3r,
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA
  ) public MachineryReady(_mechanicsRegistry) Keep3r(_keep3r) {
    _setKeep3rRequirements(_bond, _minBond, _earned, _age, _onlyEOA);
  }

  // Keep3r Setters
  function setKeep3r(address _keep3r) external override onlyGovernor {
    _setKeep3r(_keep3r);
  }

  function setKeep3rRequirements(
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA
  ) external override onlyGovernor {
    _setKeep3rRequirements(_bond, _minBond, _earned, _age, _onlyEOA);
  }

  // Setters
  function addValidJob(
    address _job,
    uint256 _maxCredits,
    uint256 _rewardMultiplier
  ) external override onlyGovernorOrMechanic {
    require(!_validJobs.contains(_job), 'Keep3rProxyJob::add-valid-job:job-already-added');
    _validJobs.add(_job);
    _setJobMaxCredits(_job, _maxCredits);
    _setJobRewardMultiplier(_job, _rewardMultiplier);
    emit AddValidJob(_job, _maxCredits);
  }

  function removeValidJob(address _job) external override onlyGovernorOrMechanic {
    require(_validJobs.contains(_job), 'Keep3rProxyJob::remove-valid-job:job-not-found');
    _validJobs.remove(_job);

    if (maxCredits[_job] > 0) {
      delete usedCredits[_job];
      delete maxCredits[_job];
    }
    emit RemoveValidJob(_job);
  }

  function setJobMaxCredits(address _job, uint256 _maxCredits) external override onlyGovernorOrMechanic {
    _setJobMaxCredits(_job, _maxCredits);
    emit SetJobMaxCredits(_job, _maxCredits);
  }

  function _setJobMaxCredits(address _job, uint256 _maxCredits) internal {
    usedCredits[_job] = 0;
    maxCredits[_job] = _maxCredits;
  }

  function setJobRewardMultiplier(address _job, uint256 _rewardMultiplier) external override onlyGovernorOrMechanic {
    _setJobRewardMultiplier(_job, _rewardMultiplier);
    emit SetJobRewardMultiplier(_job, _rewardMultiplier);
  }

  function _setJobRewardMultiplier(address _job, uint256 _rewardMultiplier) internal {
    require(_rewardMultiplier <= MAX_REWARD_MULTIPLIER, 'Keep3rProxyJob::set-reward-multiplier:multiplier-exceeds-max');
    rewardMultiplier[_job] = _rewardMultiplier;
  }

  // Getters
  function jobs() public view override returns (address[] memory validJobs) {
    validJobs = new address[](_validJobs.length());
    for (uint256 i; i < _validJobs.length(); i++) {
      validJobs[i] = _validJobs.at(i);
    }
  }

  // Keep3r-Job actions
  function workable(address _job) external override notPaused returns (bool _workable) {
    require(isValidJob(_job), 'Keep3rProxyJob::workable:invalid-job');
    return IKeep3rJob(_job).workable();
  }

  function work(address _job, bytes calldata _workData) external override returns (uint256 _credits) {
    return workForBond(_job, _workData);
  }

  function workForBond(address _job, bytes calldata _workData) public override notPaused onlyKeeper returns (uint256 _credits) {
    _credits = _work(_job, _workData, false);
    _paysKeeperAmount(msg.sender, _credits);
  }

  function workForTokens(address _job, bytes calldata _workData) external override notPaused onlyKeeper returns (uint256 _credits) {
    _credits = _work(_job, _workData, true);
    _paysKeeperInTokens(msg.sender, _credits);
  }

  function _work(
    address _job,
    bytes calldata _workData,
    bool _workForTokens
  ) internal returns (uint256 _credits) {
    require(isValidJob(_job), 'Keep3rProxyJob::work:invalid-job');

    uint256 _initialGas = gasleft();

    IKeep3rJob(_job).work(_workData);

    _credits = _calculateCredits(_job, _initialGas);

    _updateCredits(_job, _credits);
    emit Worked(_job, msg.sender, _credits, _workForTokens);
  }

  function _updateCredits(address _job, uint256 _credits) internal {
    // skip check if job's maxCredits is 0 (not limited)
    if (maxCredits[_job] == 0) return;
    usedCredits[_job] = usedCredits[_job].add(_credits);
    require(usedCredits[_job] <= maxCredits[_job], 'Keep3rProxyJob::update-credits:used-credits-exceed-max-credits');
  }

  // View helpers
  function isValidJob(address _job) public view override returns (bool) {
    return _validJobs.contains(_job);
  }

  function _calculateCredits(address _job, uint256 _initialGas) internal view returns (uint256 _credits) {
    // Gets default credits from KP3R_Helper and applies job reward multiplier
    return _getQuoteLimitFor(msg.sender, _initialGas).mul(rewardMultiplier[_job]).div(PRECISION);
  }
}
