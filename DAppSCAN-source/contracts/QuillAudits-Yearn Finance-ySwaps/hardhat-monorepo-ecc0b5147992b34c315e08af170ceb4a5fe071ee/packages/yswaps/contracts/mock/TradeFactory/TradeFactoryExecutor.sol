// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../../TradeFactory/TradeFactoryExecutor.sol';
import './TradeFactoryPositionsHandler.sol';

contract TradeFactoryExecutorMock is TradeFactoryPositionsHandlerMock, TradeFactoryExecutor {
  constructor(
    address _masterAdmin, 
    address _swapperAdder, 
    address _swapperSetter, 
    address _strategyModifier, 
    address _mechanicsRegistry
  ) 
    TradeFactoryPositionsHandlerMock(_masterAdmin, _swapperAdder, _swapperSetter, _strategyModifier)
    TradeFactoryExecutor(_mechanicsRegistry) {}
}
