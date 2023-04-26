// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4 <0.9.0;

interface ISwapperEnabled {
  error NotTradeFactory();

  function tradeFactory() external returns (address _tradeFactory);

  function swapper() external returns (string memory _swapper);

  function setSwapper(string calldata _swapper, bool _migrateSwaps) external;

  function setTradeFactory(address _tradeFactory) external;

  function enableTrade(address _tokenIn, address _tokenOut) external;

  function disableTrade(address _tokenIn, address _tokenOut) external;

  function disableTradeCallback(address _tokenIn, address _tokenOut) external;
}
