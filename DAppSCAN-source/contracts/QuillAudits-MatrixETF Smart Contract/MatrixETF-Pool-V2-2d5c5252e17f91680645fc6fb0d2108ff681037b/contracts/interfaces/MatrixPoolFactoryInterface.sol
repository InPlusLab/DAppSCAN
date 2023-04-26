// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MatrixPoolInterface.sol";

interface MatrixPoolFactoryInterface {
  function newPool(
    string calldata _name,
    string calldata _symbol,
    address _controller,
    uint256 _minWeightPerSecond,
    uint256 _maxWeightPerSecond
  ) external returns (MatrixPoolInterface);
}
