// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@yearn/contract-utils/contracts/abstract/MachineryReady.sol';
import '@yearn/contract-utils/contracts/interfaces/keep3r/IKeep3rV1Helper.sol';
import '@yearn/contract-utils/contracts/keep3r/Keep3rAbstract.sol';

import '../../interfaces/jobs/v2/IV2Keeper.sol';
import '../../interfaces/jobs/v2/IV2Keep3rJob.sol';

import '../../interfaces/yearn/IBaseStrategy.sol';
import '../../interfaces/oracle/IYOracle.sol';
import '../../interfaces/keep3r/IChainLinkFeed.sol';

abstract contract V2Keep3rJob is MachineryReady, Keep3r, IV2Keep3rJob {
  using EnumerableSet for EnumerableSet.AddressSet;

  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public override fastGasOracle = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

  uint256 public constant PRECISION = 1_000;
  uint256 public constant MAX_REWARD_MULTIPLIER = 1 * PRECISION; // 1x max reward multiplier
  uint256 public override rewardMultiplier = 850;

  address public override v2Keeper;

  address public yOracle;

  EnumerableSet.AddressSet internal _availableStrategies;

  mapping(address => uint256) public requiredAmount;
  mapping(address => uint256) public lastWorkAt;

  // custom cost oracle calcs
  mapping(address => address) public costToken;
  mapping(address => address) public costPair;

  uint256 public workCooldown;

  constructor(
    address _mechanicsRegistry,
    address _yOracle,
    address _keep3r,
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA,
    address _v2Keeper,
    uint256 _workCooldown
  ) MachineryReady(_mechanicsRegistry) Keep3r(_keep3r) {
    _setYOracle(_yOracle);
    _setKeep3rRequirements(_bond, _minBond, _earned, _age, _onlyEOA);
    v2Keeper = _v2Keeper;
    if (_workCooldown > 0) _setWorkCooldown(_workCooldown);
  }

  // Keep3r Setters
  function setKeep3r(address _keep3r) external override onlyGovernor {
    _setKeep3r(_keep3r);
  }

  function setV2Keep3r(address _v2Keeper) external override onlyGovernor {
    v2Keeper = _v2Keeper;
  }

  function setYOracle(address _yOracle) external override onlyGovernor {
    _setYOracle(_yOracle);
  }

  function _setYOracle(address _yOracle) internal {
    yOracle = _yOracle;
  }

  function setFastGasOracle(address _fastGasOracle) external override onlyGovernor {
    require(_fastGasOracle != address(0), 'V2Keep3rJob::set-fas-gas-oracle:not-zero-address');
    fastGasOracle = _fastGasOracle;
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
    require(_rewardMultiplier <= MAX_REWARD_MULTIPLIER, 'V2Keep3rJob::set-reward-multiplier:multiplier-exceeds-max');
    rewardMultiplier = _rewardMultiplier;
  }

  // Setters
  function setWorkCooldown(uint256 _workCooldown) external override onlyGovernorOrMechanic {
    _setWorkCooldown(_workCooldown);
  }

  function _setWorkCooldown(uint256 _workCooldown) internal {
    require(_workCooldown > 0, 'V2Keep3rJob::set-work-cooldown:should-not-be-zero');
    workCooldown = _workCooldown;
  }

  // Governor
  function addStrategies(
    address[] calldata _strategies,
    uint256[] calldata _requiredAmounts,
    address[] calldata _costTokens,
    address[] calldata _costPairs
  ) external override onlyGovernorOrMechanic {
    require(_strategies.length == _requiredAmounts.length, 'V2Keep3rJob::add-strategies:strategies-required-amounts-different-length');
    for (uint256 i; i < _strategies.length; i++) {
      _addStrategy(_strategies[i], _requiredAmounts[i], _costTokens[i], _costPairs[i]);
    }
  }

  function addStrategy(
    address _strategy,
    uint256 _requiredAmount,
    address _costToken,
    address _costPair
  ) external override onlyGovernorOrMechanic {
    _addStrategy(_strategy, _requiredAmount, _costToken, _costPair);
  }

  function _addStrategy(
    address _strategy,
    uint256 _requiredAmount,
    address _costToken,
    address _costPair
  ) internal {
    require(!_availableStrategies.contains(_strategy), 'V2Keep3rJob::add-strategy:strategy-already-added');
    _setRequiredAmount(_strategy, _requiredAmount);
    _setCostTokenAndPair(_strategy, _costToken, _costPair);
    emit StrategyAdded(_strategy, _requiredAmount);
    _availableStrategies.add(_strategy);
  }

  function updateRequiredAmounts(address[] calldata _strategies, uint256[] calldata _requiredAmounts) external override onlyGovernorOrMechanic {
    require(_strategies.length == _requiredAmounts.length, 'V2Keep3rJob::update-strategies:strategies-required-amounts-different-length');
    for (uint256 i; i < _strategies.length; i++) {
      _updateRequiredAmount(_strategies[i], _requiredAmounts[i]);
    }
  }

  function updateRequiredAmount(address _strategy, uint256 _requiredAmount) external override onlyGovernorOrMechanic {
    _updateRequiredAmount(_strategy, _requiredAmount);
  }

  function _updateRequiredAmount(address _strategy, uint256 _requiredAmount) internal {
    require(_availableStrategies.contains(_strategy), 'V2Keep3rJob::update-required-amount:strategy-not-added');
    _setRequiredAmount(_strategy, _requiredAmount);
    emit StrategyModified(_strategy, _requiredAmount);
  }

  function updateCostTokenAndPair(
    address _strategy,
    address _costToken,
    address _costPair
  ) external override onlyGovernorOrMechanic {
    _updateCostTokenAndPair(_strategy, _costToken, _costPair);
  }

  function _updateCostTokenAndPair(
    address _strategy,
    address _costToken,
    address _costPair
  ) internal {
    require(_availableStrategies.contains(_strategy), 'V2Keep3rJob::update-required-amount:strategy-not-added');
    _setCostTokenAndPair(_strategy, _costToken, _costPair);
  }

  function removeStrategy(address _strategy) external override onlyGovernorOrMechanic {
    require(_availableStrategies.contains(_strategy), 'V2Keep3rJob::remove-strategy:strategy-not-added');
    delete requiredAmount[_strategy];
    _availableStrategies.remove(_strategy);
    emit StrategyRemoved(_strategy);
  }

  function _setRequiredAmount(address _strategy, uint256 _requiredAmount) internal {
    requiredAmount[_strategy] = _requiredAmount;
  }

  function _setCostTokenAndPair(
    address _strategy,
    address _costToken,
    address _costPair
  ) internal {
    costToken[_strategy] = _costToken;
    costPair[_strategy] = _costPair;
  }

  // Getters
  function strategies() public view override returns (address[] memory _strategies) {
    _strategies = new address[](_availableStrategies.length());
    for (uint256 i; i < _availableStrategies.length(); i++) {
      _strategies[i] = _availableStrategies.at(i);
    }
  }

  // Keeper view actions (internal)
  function _workable(address _strategy) internal view virtual returns (bool) {
    require(_availableStrategies.contains(_strategy), 'V2Keep3rJob::workable:strategy-not-added');
    if (workCooldown == 0 || block.timestamp > lastWorkAt[_strategy] + workCooldown) return true;
    return false;
  }

  // Get eth costs
  function _getCallCosts(address _strategy) internal view returns (uint256 _callCost) {
    if (requiredAmount[_strategy] == 0) return 0;
    uint256 _ethCost = requiredAmount[_strategy] * uint256(IChainLinkFeed(fastGasOracle).latestAnswer());
    if (costToken[_strategy] == address(0)) return _ethCost;
    return IYOracle(yOracle).getAmountOut(costPair[_strategy], WETH, _ethCost, costToken[_strategy]);
  }

  // Keep3r actions
  function _workInternal(address _strategy) internal returns (uint256 _credits) {
    uint256 _initialGas = gasleft();
    require(_workable(_strategy), 'V2Keep3rJob::work:not-workable');

    _work(_strategy);

    _credits = _calculateCredits(_initialGas);

    emit Worked(_strategy, msg.sender, _credits);
  }

  function _calculateCredits(uint256 _initialGas) internal view returns (uint256 _credits) {
    // Gets default credits from KP3R_Helper and applies job reward multiplier
    return (_getQuoteLimitFor(msg.sender, _initialGas) * rewardMultiplier) / PRECISION;
  }

  function _forceWork(address _strategy) internal {
    _work(_strategy);
    emit ForceWorked(_strategy);
  }

  function _work(address _strategy) internal virtual {}
}
