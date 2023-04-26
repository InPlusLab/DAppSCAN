// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@yearn/contract-utils/contracts/abstract/UtilsReady.sol';
import '@yearn/contract-utils/contracts/keep3r/Keep3rAbstract.sol';
import '../../utils/GasPriceLimited.sol';

import '../../interfaces/jobs/IKeep3rJob.sol';
import '../../interfaces/oracle/IOracleBondedKeeper.sol';
import '../../interfaces/oracle/IPartialKeep3rV1OracleJob.sol';

contract FixedPartialKeep3rV1OracleJob is UtilsReady, Keep3r, IPartialKeep3rV1OracleJob {
  using SafeMath for uint256;

  uint256 public constant PRECISION = 1_000;
  uint256 public constant MAX_REWARD_MULTIPLIER = 1 * PRECISION; // 1x max reward multiplier
  uint256 public override rewardMultiplier = MAX_REWARD_MULTIPLIER;

  EnumerableSet.AddressSet internal _availablePairs;

  address public immutable override oracleBondedKeeper = 0xA8646cE5d983E996EbA22eb39e5956653ec63762;

  // 0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44 = Keep3rV1

  constructor() public UtilsReady() Keep3r(0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44) {
    _setKeep3rRequirements(0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44, 200 ether, 0, 0, false);
  }

  // Keep3r Setters
  function setKeep3r(address _keep3r) external override onlyGovernor {
    _keep3r; // shh
    revert('FixedPartialKeep3rV1OracleJob::set-keep3r:fixed');
  }

  function setKeep3rRequirements(
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA
  ) external override onlyGovernor {
    _bond; // shh
    _minBond; // shh
    _earned; // shh
    _age; // shh
    _onlyEOA; // shh
    revert('FixedPartialKeep3rV1OracleJob::set-keep3r-requirements:fixed');
  }

  function setRewardMultiplier(uint256 _rewardMultiplier) external override onlyGovernor {
    _setRewardMultiplier(_rewardMultiplier);
    emit SetRewardMultiplier(_rewardMultiplier);
  }

  function _setRewardMultiplier(uint256 _rewardMultiplier) internal {
    require(_rewardMultiplier <= MAX_REWARD_MULTIPLIER, 'FixedPartialKeep3rV1OracleJob::set-reward-multiplier:multiplier-exceeds-max');
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
    require(!_availablePairs.contains(_pair), 'FixedPartialKeep3rV1OracleJob::add-pair:pair-already-added');
    _availablePairs.add(_pair);
    emit PairAdded(_pair);
  }

  function removePair(address _pair) external override onlyGovernor {
    require(_availablePairs.contains(_pair), 'FixedPartialKeep3rV1OracleJob::remove-pair:pair-not-found');
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
    require(_availablePairs.contains(_pair), 'FixedPartialKeep3rV1OracleJob::workable:pair-not-found');
    return IOracleBondedKeeper(oracleBondedKeeper).workable(_pair);
  }

  // Keeper actions
  function _work(address _pair) internal returns (uint256 _credits) {
    uint256 _initialGas = gasleft();

    require(_workable(_pair), 'FixedPartialKeep3rV1OracleJob::work:not-workable');

    require(_updatePair(_pair), 'FixedPartialKeep3rV1OracleJob::work:pair-not-updated');

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
    require(_updatePair(_pair), 'FixedPartialKeep3rV1OracleJob::force-work:pair-not-updated');
    emit ForceWorked(_pair);
  }

  function _updatePair(address _pair) internal returns (bool _updated) {
    return IOracleBondedKeeper(oracleBondedKeeper).updatePair(_pair);
  }
}
