// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@yearn/contract-utils/contracts/abstract/MachineryReady.sol';
import '@yearn/contract-utils/contracts/keep3r/Keep3rAbstract.sol';

import '../interfaces/jobs/ICrvStrategyKeep3rJob.sol';
import '../interfaces/keep3r/IKeep3rEscrow.sol';

import '../interfaces/yearn/IV1Controller.sol';
import '../interfaces/yearn/IV1Vault.sol';
import '../interfaces/crv/ICrvStrategy.sol';
import '../interfaces/crv/ICrvClaimable.sol';

contract CrvStrategyKeep3rJob is MachineryReady, Keep3r, ICrvStrategyKeep3rJob {
  using EnumerableSet for EnumerableSet.AddressSet;

  uint256 public constant PRECISION = 1_000;
  uint256 public constant MAX_REWARD_MULTIPLIER = 1 * PRECISION; // 1x max reward multiplier
  uint256 public override rewardMultiplier = MAX_REWARD_MULTIPLIER;

  mapping(address => uint256) public override requiredHarvest;
  mapping(address => uint256) public override requiredEarn;
  mapping(address => uint256) public override lastWorkAt;

  uint256 public override maxHarvestPeriod;
  uint256 public override lastHarvest;
  uint256 public override harvestCooldown;

  EnumerableSet.AddressSet internal _availableStrategies;

  constructor(
    address _mechanicsRegistry,
    address _keep3r,
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA,
    uint256 _maxHarvestPeriod,
    uint256 _harvestCooldown
  ) MachineryReady(_mechanicsRegistry) Keep3r(_keep3r) {
    _setKeep3rRequirements(_bond, _minBond, _earned, _age, _onlyEOA);
    _setMaxHarvestPeriod(_maxHarvestPeriod);
    _setHarvestCooldown(_harvestCooldown);
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

  function setRewardMultiplier(uint256 _rewardMultiplier) external override onlyGovernorOrMechanic {
    _setRewardMultiplier(_rewardMultiplier);
    emit SetRewardMultiplier(_rewardMultiplier);
  }

  function _setRewardMultiplier(uint256 _rewardMultiplier) internal {
    require(_rewardMultiplier <= MAX_REWARD_MULTIPLIER, 'CrvStrategyKeep3rJob::set-reward-multiplier:multiplier-exceeds-max');
    rewardMultiplier = _rewardMultiplier;
  }

  // Setters
  function addStrategies(
    address[] calldata _strategies,
    uint256[] calldata _requiredHarvests,
    uint256[] calldata _requiredEarns
  ) external override onlyGovernorOrMechanic {
    require(
      _strategies.length == _requiredHarvests.length && _strategies.length == _requiredEarns.length,
      'CrvStrategyKeep3rJob::add-strategies:strategies-required-harvests-and-earns-different-length'
    );
    for (uint256 i; i < _strategies.length; i++) {
      _addStrategy(_strategies[i], _requiredHarvests[i], _requiredEarns[i]);
    }
  }

  function addStrategy(
    address _strategy,
    uint256 _requiredHarvest,
    uint256 _requiredEarn
  ) external override onlyGovernorOrMechanic {
    _addStrategy(_strategy, _requiredHarvest, _requiredEarn);
  }

  function _addStrategy(
    address _strategy,
    uint256 _requiredHarvest,
    uint256 _requiredEarn
  ) internal {
    require(requiredHarvest[_strategy] == 0, 'CrvStrategyKeep3rJob::add-strategy:strategy-already-added');
    _setRequiredHarvest(_strategy, _requiredHarvest);
    _setRequiredEarn(_strategy, _requiredEarn);
    _availableStrategies.add(_strategy);
    lastWorkAt[_strategy] = block.timestamp;
    emit StrategyAdded(_strategy, _requiredHarvest, _requiredEarn);
  }

  function updateStrategies(
    address[] calldata _strategies,
    uint256[] calldata _requiredHarvests,
    uint256[] calldata _requiredEarns
  ) external override onlyGovernorOrMechanic {
    require(
      _strategies.length == _requiredHarvests.length && _strategies.length == _requiredEarns.length,
      'CrvStrategyKeep3rJob::update-strategies:strategies-required-harvests-and-earns-different-length'
    );
    for (uint256 i; i < _strategies.length; i++) {
      _updateStrategy(_strategies[i], _requiredHarvests[i], _requiredEarns[i]);
    }
  }

  function updateStrategy(
    address _strategy,
    uint256 _requiredHarvest,
    uint256 _requiredEarn
  ) external override onlyGovernorOrMechanic {
    _updateStrategy(_strategy, _requiredHarvest, _requiredEarn);
  }

  function _updateStrategy(
    address _strategy,
    uint256 _requiredHarvest,
    uint256 _requiredEarn
  ) internal {
    require(requiredHarvest[_strategy] > 0, 'CrvStrategyKeep3rJob::update-required-harvest:strategy-not-added');
    _setRequiredHarvest(_strategy, _requiredHarvest);
    _setRequiredEarn(_strategy, _requiredEarn);
    emit StrategyModified(_strategy, _requiredHarvest, _requiredEarn);
  }

  function removeStrategy(address _strategy) external override onlyGovernorOrMechanic {
    require(requiredHarvest[_strategy] > 0, 'CrvStrategyKeep3rJob::remove-strategy:strategy-not-added');
    requiredHarvest[_strategy] = 0;
    _availableStrategies.remove(_strategy);
    emit StrategyRemoved(_strategy);
  }

  function _setRequiredHarvest(address _strategy, uint256 _requiredHarvest) internal {
    require(_requiredHarvest > 0, 'CrvStrategyKeep3rJob::set-required-harvest:should-not-be-zero');
    requiredHarvest[_strategy] = _requiredHarvest;
  }

  function _setRequiredEarn(address _strategy, uint256 _requiredEarn) internal {
    require(_requiredEarn > 0, 'CrvStrategyKeep3rJob::set-required-earn:should-not-be-zero');
    requiredEarn[_strategy] = _requiredEarn;
  }

  function setMaxHarvestPeriod(uint256 _maxHarvestPeriod) external override onlyGovernorOrMechanic {
    _setMaxHarvestPeriod(_maxHarvestPeriod);
  }

  function _setMaxHarvestPeriod(uint256 _maxHarvestPeriod) internal {
    require(_maxHarvestPeriod > 0, 'CrvStrategyKeep3rJob::set-max-harvest-period:should-not-be-zero');
    maxHarvestPeriod = _maxHarvestPeriod;
  }

  function setHarvestCooldown(uint256 _harvestCooldown) external override onlyGovernorOrMechanic {
    _setHarvestCooldown(_harvestCooldown);
  }

  function _setHarvestCooldown(uint256 _harvestCooldown) internal {
    harvestCooldown = _harvestCooldown;
  }

  // Getters
  function strategies() public view override returns (address[] memory _strategies) {
    _strategies = new address[](_availableStrategies.length());
    for (uint256 i; i < _availableStrategies.length(); i++) {
      _strategies[i] = _availableStrategies.at(i);
    }
  }

  // Keeper view actions
  function calculateHarvest(address _strategy) public override returns (uint256 _amount) {
    require(requiredHarvest[_strategy] > 0, 'CrvStrategyKeep3rJob::calculate-harvest:strategy-not-added');
    address _gauge = ICrvStrategy(_strategy).gauge();
    address _voter = ICrvStrategy(_strategy).voter();
    return ICrvClaimable(_gauge).claimable_tokens(_voter);
  }

  function workable(address _strategy) external override notPaused returns (bool) {
    return _workable(_strategy);
  }

  function _workable(address _strategy) internal returns (bool) {
    require(requiredHarvest[_strategy] > 0, 'CrvStrategyKeep3rJob::workable:strategy-not-added');
    // ensures no other strategy has been harvested for at least the harvestCooldown
    if (block.timestamp < lastHarvest + harvestCooldown) return false;
    // if strategy has exceeded maxHarvestPeriod, force workable true
    if (block.timestamp > lastWorkAt[_strategy] + maxHarvestPeriod) return true;
    return calculateHarvest(_strategy) >= requiredHarvest[_strategy];
  }

  // Keeper actions
  function _work(address _strategy) internal returns (uint256 _credits) {
    uint256 _initialGas = gasleft();
    require(_workable(_strategy), 'CrvStrategyKeep3rJob::harvest:not-workable');

    // Checks if vault has enough available amount to earn
    address controller = ICrvStrategy(_strategy).controller();
    address want = ICrvStrategy(_strategy).want();
    address vault = IV1Controller(controller).vaults(want);
    uint256 available = IV1Vault(vault).available();
    if (available >= requiredEarn[_strategy]) {
      IV1Vault(vault).earn();
    }

    _harvest(_strategy);

    _credits = _calculateCredits(_initialGas);

    emit Worked(_strategy, msg.sender, _credits);
  }

  function work(address _strategy) external override notPaused onlyKeeper(msg.sender) returns (uint256 _credits) {
    _credits = _work(_strategy);
    _paysKeeperAmount(msg.sender, _credits);
  }

  function _calculateCredits(uint256 _initialGas) internal view returns (uint256 _credits) {
    // Gets default credits from KP3R_Helper and applies job reward multiplier
    return (_getQuoteLimitFor(msg.sender, _initialGas) * rewardMultiplier) / PRECISION;
  }

  // Mechanics keeper bypass
  function forceWork(address _strategy) external override onlyGovernorOrMechanic {
    _harvest(_strategy);
    emit ForceWorked(_strategy);
  }

  function _harvest(address _strategy) internal {
    ICrvStrategy(_strategy).harvest();
    lastWorkAt[_strategy] = block.timestamp;
    lastHarvest = block.timestamp;
  }
}
