pragma solidity >=0.7.0;

abstract contract IExchange {
  function swapDaiForToken(
    address asset,
    uint256 amount,
    uint256 receiveAtLeast,
    address callee,
    bytes calldata withData
  ) external virtual;

  function swapTokenForDai(
    address asset,
    uint256 amount,
    uint256 receiveAtLeast,
    address callee,
    bytes calldata withData
  ) external virtual;
}
