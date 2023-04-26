// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./BPoolInterface.sol";

interface MatrixPoolInterface is BPoolInterface {
  function initialize(
    string calldata name,
    string calldata symbol,
    uint256 minWeightPerSecond,
    uint256 maxWeightPerSecond
  ) external;

  function bind(
    address,
    uint256,
    uint256,
    uint256,
    uint256
  ) external;

  function setDynamicWeight(
    address token,
    uint256 targetDenorm,
    uint256 fromTimestamp,
    uint256 targetTimestamp
  ) external;

  function getDynamicWeightSettings(address token)
    external
    view
    returns (
      uint256 fromTimestamp,
      uint256 targetTimestamp,
      uint256 fromDenorm,
      uint256 targetDenorm
    );

  function getMinWeight() external view override returns (uint256);

  function getWeightPerSecondBounds() external view returns (uint256, uint256);

  function setWeightPerSecondBounds(uint256, uint256) external;

  function setWrapper(address, bool) external;

  function getWrapperMode() external view returns (bool);
}
