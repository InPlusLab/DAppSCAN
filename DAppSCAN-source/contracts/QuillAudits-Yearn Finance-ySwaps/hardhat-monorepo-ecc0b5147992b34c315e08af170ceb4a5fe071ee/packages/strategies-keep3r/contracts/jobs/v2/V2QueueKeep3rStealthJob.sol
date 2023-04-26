// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@yearn/contract-utils/contracts/abstract/MachineryReady.sol';
import '@yearn/contract-utils/contracts/interfaces/keep3r/IKeep3rV1Helper.sol';
import '@yearn/contract-utils/contracts/keep3r/Keep3rAbstract.sol';
import '@lbertenasco/bonded-stealth-tx/contracts/utils/OnlyStealthRelayer.sol';
import '../../interfaces/jobs/v2/IV2Keeper.sol';
import '../../interfaces/stealth/IStealthRelayer.sol';

import '../../interfaces/jobs/v2/IV2QueueKeep3rJob.sol';
import '../../interfaces/yearn/IBaseStrategy.sol';
import '../../interfaces/keep3r/IChainLinkFeed.sol';

abstract contract V2QueueKeep3rStealthJob is MachineryReady, OnlyStealthRelayer, Keep3r, IV2QueueKeep3rJob {
  using EnumerableSet for EnumerableSet.AddressSet;

  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public override fastGasOracle = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

  uint256 public constant PRECISION = 1_000;
  uint256 public constant MAX_REWARD_MULTIPLIER = 1 * PRECISION; // 1x max reward multiplier
  uint256 public override rewardMultiplier = MAX_REWARD_MULTIPLIER;

  address public yOracle;
  address public v2Keeper;
  address public oracle;

  EnumerableSet.AddressSet internal _availableStrategies;

  // strategy queue strategies
  mapping(address => address[]) public strategyQueue;
  // strategy queue amounts
  mapping(address => uint256[]) public strategyAmounts;
  // last strategy workAt timestamp
  mapping(address => uint256) public lastWorkAt;

  uint256 public workCooldown;

  constructor(
    address _mechanicsRegistry,
    address _stealthRelayer,
    address _yOracle,
    address _keep3r,
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA,
    address _v2Keeper,
    uint256 _workCooldown
  ) MachineryReady(_mechanicsRegistry) OnlyStealthRelayer(_stealthRelayer) Keep3r(_keep3r) {
    _setYOracle(_yOracle);
    _setKeep3rRequirements(_bond, _minBond, _earned, _age, _onlyEOA);
    v2Keeper = _v2Keeper;
    if (_workCooldown > 0) _setWorkCooldown(_workCooldown);
    revert('yOracle-not-fully-implemented');
  }

  // Stealth Relayer Setters
  function setStealthRelayer(address _stealthRelayer) external override onlyGovernor {
    _setStealthRelayer(_stealthRelayer);
  }

  // TODO:
  // - add strategies cost(token & pair)
  // - add cost calculations though yOracle in each specific costToken
  // yOracle
  function setYOracle(address _yOracle)
    external
    /*override*/
    onlyGovernor
  {
    _setYOracle(_yOracle);
  }

  function _setYOracle(address _yOracle) internal {
    yOracle = _yOracle;
  }

  // Keep3r Setters
  function setKeep3r(address _keep3r) external override onlyGovernor {
    _setKeep3r(_keep3r);
  }

  function setV2Keep3r(address _v2Keeper) external override onlyGovernor {
    v2Keeper = _v2Keeper;
  }

  function setFastGasOracle(address _fastGasOracle) external override onlyGovernor {
    require(_fastGasOracle != address(0), 'V2QueueKeep3rJob::set-fas-gas-oracle:not-zero-address');
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
    require(_rewardMultiplier <= MAX_REWARD_MULTIPLIER, 'V2QueueKeep3rJob::set-reward-multiplier:multiplier-exceeds-max');
    rewardMultiplier = _rewardMultiplier;
  }

  // Setters
  function setWorkCooldown(uint256 _workCooldown) external override onlyGovernorOrMechanic {
    _setWorkCooldown(_workCooldown);
  }

  function _setWorkCooldown(uint256 _workCooldown) internal {
    require(_workCooldown > 0, 'V2QueueKeep3rJob::set-work-cooldown:should-not-be-zero');
    workCooldown = _workCooldown;
  }

  // Governor
  function setStrategy(
    address _strategy,
    address[] calldata _strategies,
    uint256[] calldata _requiredAmounts
  ) external override onlyGovernorOrMechanic {
    _setStrategy(_strategy, _strategies, _requiredAmounts);
  }

  function _setStrategy(
    address _strategy,
    address[] calldata _strategies,
    uint256[] calldata _requiredAmounts
  ) internal {
    require(strategyQueue[_strategy].length == 0, 'V2QueueKeep3rJob::add-strategy:strategy-already-added');
    strategyQueue[_strategy] = _strategies;
    strategyAmounts[_strategy] = _requiredAmounts;
    _availableStrategies.add(_strategy);
  }

  function removeStrategy(address _strategy) external override onlyGovernorOrMechanic {
    require(strategyQueue[_strategy].length > 0, 'V2QueueKeep3rJob::remove-strategy:strategy-not-added');
    delete strategyQueue[_strategy];
    delete strategyAmounts[_strategy];
    _availableStrategies.remove(_strategy);
    emit StrategyRemoved(_strategy);
  }

  // Getters
  function strategies() public view override returns (address[] memory _strategies) {
    _strategies = new address[](_availableStrategies.length());
    for (uint256 i; i < _availableStrategies.length(); i++) {
      _strategies[i] = _availableStrategies.at(i);
    }
  }

  function strategyQueueList(address _strategy) public view override returns (address[] memory _strategies) {
    _strategies = new address[](strategyQueue[_strategy].length);
    for (uint256 i; i < strategyQueue[_strategy].length; i++) {
      _strategies[i] = strategyQueue[_strategy][i];
    }
  }

  // Keeper view actions (internal)
  function _mainStrategyWorkable(address _strategy) internal view virtual returns (bool) {
    require(_availableStrategies.contains(_strategy), 'V2QueueKeep3rJob::main-workable:strategy-not-added');
    require(workCooldown == 0 || block.timestamp > lastWorkAt[_strategy] + workCooldown, 'V2QueueKeep3rJob::main-workable:on-cooldown');
    return true;
  }

  function _workable(address _strategy) internal view virtual returns (bool) {
    return _mainStrategyWorkable(_strategy);
  }

  // Get eth costs
  function _getEthGasPrice() internal view returns (uint256 _ethGasPrice) {
    return uint256(IChainLinkFeed(fastGasOracle).latestAnswer());
  }

  function _strategyTrigger(address _strategy, uint256 _amount) internal view virtual returns (bool) {}

  // Keep3r actions
  function _workInternal(address _strategy) internal returns (uint256 _credits) {
    uint256 _initialGas = gasleft();
    uint256 _ethGasPrice = _getEthGasPrice();
    // Checks if main strategy is workable
    require(_mainStrategyWorkable(_strategy), 'V2QueueKeep3rJob::work:main-not-workable');
    bool mainWorked = false;

    for (uint256 _index; _index < strategyQueue[_strategy].length; _index++) {
      uint256 _ethAmount = strategyAmounts[_strategy][_index] * _ethGasPrice;
      if (_strategyTrigger(strategyQueue[_strategy][_index], _ethAmount)) {
        _work(strategyQueue[_strategy][_index]);
        if (strategyQueue[_strategy][_index] == _strategy) mainWorked = true;
      }
    }
    require(mainWorked, 'V2QueueKeep3rJob::work:main-not-worked');

    lastWorkAt[_strategy] = block.timestamp;

    _credits = _calculateCredits(_initialGas);

    emit Worked(_strategy, msg.sender, _credits);
  }

  function _calculateCredits(uint256 _initialGas) internal view returns (uint256 _credits) {
    // Gets default credits from KP3R_Helper and applies job reward multiplier
    return (_getQuoteLimitFor(tx.origin, _initialGas) * rewardMultiplier) / PRECISION;
  }

  // Mechanics keeper bypass
  function forceWork(address _strategy) external override onlyStealthRelayer {
    address _caller = IStealthRelayer(stealthRelayer).caller();
    require(isGovernor(_caller) || isMechanic(_caller), 'V2Keep3rStealthJob::forceWork:invalid-stealth-caller');
    _forceWork(_strategy);
  }

  function forceWorkUnsafe(address _strategy) external override onlyGovernorOrMechanic {
    _forceWork(_strategy);
  }

  function _forceWork(address _strategy) internal {
    _work(_strategy);
    emit ForceWorked(_strategy);
  }

  function _work(address _strategy) internal virtual {}
}
