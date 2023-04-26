// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../../swappers/Swapper.sol';

contract SwapperMock is Swapper {

  constructor(address _governor, address _tradeFactory) Swapper(_tradeFactory) Governable(_governor) {}

  // solhint-disable-next-line func-name-mixedcase
  function SWAPPER_TYPE() external view override returns (SwapperType) {
    return SwapperType.ASYNC;
  }

  function modifierOnlyTradeFactory() external onlyTradeFactory { }
}
