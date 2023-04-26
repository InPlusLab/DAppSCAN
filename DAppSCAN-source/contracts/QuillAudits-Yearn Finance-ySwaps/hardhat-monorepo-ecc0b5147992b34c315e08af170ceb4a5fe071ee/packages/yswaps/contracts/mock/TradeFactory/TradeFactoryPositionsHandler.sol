// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../../TradeFactory/TradeFactoryPositionsHandler.sol';
import './TradeFactorySwapperHandler.sol';

contract TradeFactoryPositionsHandlerMock is TradeFactorySwapperHandlerMock, TradeFactoryPositionsHandler {
  constructor(
    address _masterAdmin, 
    address _swapperAdder, 
    address _swapperSetter,
    address _strategyModifier
  ) 
  TradeFactoryPositionsHandler(
    _strategyModifier
  ) 
  TradeFactorySwapperHandlerMock(
    _masterAdmin, 
    _swapperAdder, 
    _swapperSetter
  ) {}

}
