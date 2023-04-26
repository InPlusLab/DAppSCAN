// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@yearn/contract-utils/contracts/abstract/UtilsReady.sol';
import '@yearn/contract-utils/contracts/keep3r/Keep3rAbstract.sol';
import '../../utils/GasPriceLimited.sol';

import '../../interfaces/jobs/IKeep3rJob.sol';
import '../../interfaces/oracle/IOracleBondedKeeper.sol';
import '../../interfaces/oracle/IPartialKeep3rV1OracleJob.sol';

contract PartialKeep3rV1OracleJob is UtilsReady, Keep3r, IPartialKeep3rV1OracleJob {
  using SafeMath for uint256;

  uint256 public constant PRECISION = 1_000;
  uint256 public constant MAX_REWARD_MULTIPLIER = 1 * PRECISION; // 1x max reward multiplier
  uint256 public override rewardMultiplier = MAX_REWARD_MULTIPLIER;

  EnumerableSet.AddressSet internal _availablePairs;

  address public immutable override oracleBondedKeeper;

  constructor(
    address _keep3r,
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA,
    address _oracleBondedKeeper
  ) public UtilsReady() Keep3r(_keep3r) {
    _setKeep3rRequirements(_bond, _minBond, _earned, _age, _onlyEOA);
    oracleBondedKeeper = _oracleBondedKeeper;
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

  function setRewardMultiplier(uint256 _rewardMultiplier) external override onlyGovernor {
    _setRewardMultiplier(_rewardMultiplier);
    emit SetRewardMultiplier(_rewardMultiplier);
  }

  function _setRewardMultiplier(uint256 _rewardMultiplier) internal {
    require(_rewardMultiplier <= MAX_REWARD_MULTIPLIER, 'PartialKeep3rV1OracleJob::set-reward-multiplier:multiplier-exceeds-max');
    rewardMultiplier = _rewardMultiplier;
  }

  // Setters
  function addPairs(address[] calldata _pairs) external override onlyGovernor {
    for (uint256 i; i < _pairs.length; i++) {
      _addPair(_pairs[i]);
    }
  }

  function addPair(address _pair) external override onlyGovernor {
    _addPair(_pair);
  }

  function _addPair(address _pair) internal {
    require(!_availablePairs.contains(_pair), 'PartialKeep3rV1OracleJob::add-pair:pair-already-added');
    _availablePairs.add(_pair);
    emit PairAdded(_pair);
  }

  function removePair(address _pair) external override onlyGovernor {
    require(_availablePairs.contains(_pair), 'PartialKeep3rV1OracleJob::remove-pair:pair-not-found');
    _availablePairs.remove(_pair);
    emit PairRemoved(_pair);
  }

  // Getters
  function pairs() public view override returns (address[] memory _pairs) {
    _pairs = new address[](_availablePairs.length());
    for (uint256 i; i < _availablePairs.length(); i++) {
      _pairs[i] = _availablePairs.at(i);
    }
  }

  // Keeper view actions
  function workable(address _pair) external view override notPaused returns (bool) {
    return _workable(_pair);
  }

  function _workable(address _pair) internal view returns (bool) {
    require(_availablePairs.contains(_pair), 'PartialKeep3rV1OracleJob::workable:pair-not-found');
    return IOracleBondedKeeper(oracleBondedKeeper).workable(_pair);
  }

  // Keeper actions
  function _work(address _pair) internal returns (uint256 _credits) {
    uint256 _initialGas = gasleft();

    require(_workable(_pair), 'PartialKeep3rV1OracleJob::work:not-workable');

    require(_updatePair(_pair), 'PartialKeep3rV1OracleJob::work:pair-not-updated');

    _credits = _calculateCredits(_initialGas);

    emit Worked(_pair, msg.sender, _credits);
  }

  function work(address _pair) public override notPaused onlyKeeper returns (uint256 _credits) {
    _credits = _work(_pair);
    _paysKeeperInTokens(msg.sender, _credits);
  }

  function _calculateCredits(uint256 _initialGas) internal view returns (uint256 _credits) {
    // Gets default credits from KP3R_Helper and applies job reward multiplier
    return _getQuoteLimitFor(msg.sender, _initialGas).mul(rewardMultiplier).div(PRECISION);
  }

  // Mechanics keeper bypass
  function forceWork(address _pair) external override onlyGovernor {
    require(_updatePair(_pair), 'PartialKeep3rV1OracleJob::force-work:pair-not-updated');
    emit ForceWorked(_pair);
  }

  function _updatePair(address _pair) internal returns (bool _updated) {
    return IOracleBondedKeeper(oracleBondedKeeper).updatePair(_pair);
  }
}
