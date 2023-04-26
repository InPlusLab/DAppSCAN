// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import '../../TradeFactory/TradeFactorySwapperHandler.sol';

contract TradeFactorySwapperHandlerMock is TradeFactorySwapperHandler {
  using EnumerableSet for EnumerableSet.AddressSet;
  
  constructor(
    address _masterAdmin, 
    address _swapperAdder, 
    address _swapperSetter
  ) TradeFactorySwapperHandler(_swapperAdder, _swapperSetter) TradeFactoryAccessManager(_masterAdmin) {}

  function addSwapperInternal(address _swapper) external {
    _swappers.add(_swapper);
  }

  function removeSwapperInternal(address _swapper) external {
    _swappers.remove(_swapper);
  }

  function addSwapperToStrategyInternal(address _swapper, address _strategy) external {
    _swapperStrategies[_swapper].add(_strategy);
  }

  function removeSwapperFromStrategyInternal(address _swapper, address _strategy) external {
    _swapperStrategies[_swapper].remove(_strategy);
  }

}
