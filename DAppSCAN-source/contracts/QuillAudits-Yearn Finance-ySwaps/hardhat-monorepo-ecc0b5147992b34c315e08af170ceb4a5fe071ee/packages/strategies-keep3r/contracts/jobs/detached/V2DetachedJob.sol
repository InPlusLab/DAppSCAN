// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4 <0.9.0;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@yearn/contract-utils/contracts/abstract/MachineryReady.sol';

import '../../interfaces/jobs/v2/IV2Keeper.sol';
import '../../interfaces/jobs/detached/IV2DetachedJob.sol';

import '../../interfaces/yearn/IBaseStrategy.sol';
import '../../interfaces/oracle/IYOracle.sol';
import '../../interfaces/utils/IBaseFee.sol';

abstract contract V2DetachedJob is MachineryReady, IV2DetachedJob {
  using EnumerableSet for EnumerableSet.AddressSet;

  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public immutable baseFeeOracle;

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
    address _baseFeeOracle,
    address _mechanicsRegistry,
    address _yOracle,
    address _v2Keeper,
    uint256 _workCooldown
  ) MachineryReady(_mechanicsRegistry) {
    baseFeeOracle = _baseFeeOracle;
    _setYOracle(_yOracle);
    v2Keeper = _v2Keeper;
    if (_workCooldown > 0) _setWorkCooldown(_workCooldown);
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

  // Setters
  function setWorkCooldown(uint256 _workCooldown) external override onlyGovernorOrMechanic {
    _setWorkCooldown(_workCooldown);
  }

  function _setWorkCooldown(uint256 _workCooldown) internal {
    if (_workCooldown == 0) revert NotZero();
    workCooldown = _workCooldown;
  }

  // Governor
  function addStrategies(
    address[] calldata _strategies,
    uint256[] calldata _requiredAmounts,
    address[] calldata _costTokens,
    address[] calldata _costPairs
  ) external override onlyGovernorOrMechanic {
    if (_strategies.length != _requiredAmounts.length) revert RequiredAmountsDifferentLength();
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
    _setRequiredAmount(_strategy, _requiredAmount);
    _setCostTokenAndPair(_strategy, _costToken, _costPair);
    emit StrategyAdded(_strategy, _requiredAmount);
    if (!_availableStrategies.add(_strategy)) revert StrategyAlreadyAdded();
  }

  function updateRequiredAmounts(address[] calldata _strategies, uint256[] calldata _requiredAmounts) external override onlyGovernorOrMechanic {
    if (_strategies.length != _requiredAmounts.length) revert RequiredAmountsDifferentLength();
    for (uint256 i; i < _strategies.length; i++) {
      _updateRequiredAmount(_strategies[i], _requiredAmounts[i]);
    }
  }

  function updateRequiredAmount(address _strategy, uint256 _requiredAmount) external override onlyGovernorOrMechanic {
    _updateRequiredAmount(_strategy, _requiredAmount);
  }

  function _updateRequiredAmount(address _strategy, uint256 _requiredAmount) internal {
    if (!_availableStrategies.contains(_strategy)) revert StrategyNotAdded();
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
    if (!_availableStrategies.contains(_strategy)) revert StrategyNotAdded();
    _setCostTokenAndPair(_strategy, _costToken, _costPair);
  }

  function removeStrategy(address _strategy) external override onlyGovernorOrMechanic {
    if (!_availableStrategies.contains(_strategy)) revert StrategyNotAdded();
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
    if (!_availableStrategies.contains(_strategy)) revert StrategyNotAdded();
    if (workCooldown == 0 || block.timestamp > lastWorkAt[_strategy] + workCooldown) return true;
    return false;
  }

  // Get eth costs
  function _getCallCosts(address _strategy) internal view returns (uint256 _callCost) {
    if (requiredAmount[_strategy] == 0) return 0;
    uint256 _ethCost = requiredAmount[_strategy] * IBaseFee(baseFeeOracle).basefee_global();
    if (costToken[_strategy] == address(0)) return _ethCost;
    return IYOracle(yOracle).getAmountOut(costPair[_strategy], WETH, _ethCost, costToken[_strategy]);
  }

  // Keep3r actions
  function _workInternal(address _strategy) internal {
    if (!_workable(_strategy)) revert NotWorkable();

    _work(_strategy);

    emit Worked(_strategy, msg.sender);
  }

  function forceWork(address _strategy) external override onlyGovernorOrMechanic {
    _work(_strategy);
    emit ForceWorked(_strategy);
  }

  function _work(address _strategy) internal virtual {}
}
