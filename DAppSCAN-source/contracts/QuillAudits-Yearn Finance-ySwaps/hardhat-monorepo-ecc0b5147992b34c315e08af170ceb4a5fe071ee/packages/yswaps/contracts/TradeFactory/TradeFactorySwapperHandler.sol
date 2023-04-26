// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import '../swappers/Swapper.sol';

import './TradeFactoryAccessManager.sol';

interface ITradeFactorySwapperHandler {
  error NotAsyncSwapper();
  error NotSyncSwapper();
  error InvalidSwapper();
  error SwapperInUse();

  function strategySyncSwapper(address _strategy) external view returns (address _swapper);

  function swappers() external view returns (address[] memory _swappersList);

  function isSwapper(address _swapper) external view returns (bool _isSwapper);

  function swapperStrategies(address _swapper) external view returns (address[] memory _strategies);

  function setStrategySyncSwapper(address _strategy, address _swapper) external;

  function addSwappers(address[] memory __swappers) external;

  function removeSwappers(address[] memory __swappers) external;
}

abstract contract TradeFactorySwapperHandler is ITradeFactorySwapperHandler, TradeFactoryAccessManager {
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public constant SWAPPER_ADDER = keccak256('SWAPPER_ADDER');
  bytes32 public constant SWAPPER_SETTER = keccak256('SWAPPER_SETTER');

  // swappers list
  EnumerableSet.AddressSet internal _swappers;
  // swapper -> strategy list (useful to know if we can safely deprecate a swapper)
  mapping(address => EnumerableSet.AddressSet) internal _swapperStrategies;
  // strategy -> sync swapper
  mapping(address => address) public override strategySyncSwapper;

  constructor(address _swapperAdder, address _swapperSetter) {
    if (_swapperAdder == address(0) || _swapperSetter == address(0)) revert CommonErrors.ZeroAddress();
    _setRoleAdmin(SWAPPER_ADDER, MASTER_ADMIN);
    _setRoleAdmin(SWAPPER_SETTER, MASTER_ADMIN);
    _setupRole(SWAPPER_ADDER, _swapperAdder);
    _setupRole(SWAPPER_SETTER, _swapperSetter);
  }

  function isSwapper(address _swapper) external view override returns (bool _isSwapper) {
    _isSwapper = _swappers.contains(_swapper);
  }

  function swappers() external view override returns (address[] memory _swappersList) {
    _swappersList = _swappers.values();
  }

  function swapperStrategies(address _swapper) external view override returns (address[] memory _strategies) {
    _strategies = _swapperStrategies[_swapper].values();
  }

  function setStrategySyncSwapper(address _strategy, address _swapper) external override onlyRole(SWAPPER_SETTER) {
    if (_strategy == address(0) || _swapper == address(0)) revert CommonErrors.ZeroAddress();
    // we check that swapper being added is async
    if (ISwapper(_swapper).SWAPPER_TYPE() != ISwapper.SwapperType.SYNC) revert NotSyncSwapper();
    // we check that swapper is not already added
    if (!_swappers.contains(_swapper)) revert InvalidSwapper();
    // remove strategy from previous swapper if any
    if (strategySyncSwapper[_strategy] != address(0)) _swapperStrategies[strategySyncSwapper[_strategy]].remove(_strategy);
    // set new strategy's sync swapper
    strategySyncSwapper[_strategy] = _swapper;
    // add strategy into new swapper
    _swapperStrategies[_swapper].add(_strategy);
  }

  function addSwappers(address[] memory __swappers) external override onlyRole(SWAPPER_ADDER) {
    for (uint256 i; i < __swappers.length; i++) {
      if (__swappers[i] == address(0)) revert CommonErrors.ZeroAddress();
      _swappers.add(__swappers[i]);
    }
  }

  function removeSwappers(address[] memory __swappers) external override onlyRole(SWAPPER_ADDER) {
    for (uint256 i; i < __swappers.length; i++) {
      if (_swapperStrategies[__swappers[i]].length() > 0) revert SwapperInUse();
      _swappers.remove(__swappers[i]);
    }
  }
}
