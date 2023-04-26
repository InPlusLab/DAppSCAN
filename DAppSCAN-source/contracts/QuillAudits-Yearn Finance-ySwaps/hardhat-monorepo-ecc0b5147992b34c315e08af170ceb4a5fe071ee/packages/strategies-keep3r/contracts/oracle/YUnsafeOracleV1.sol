// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@yearn/contract-utils/contracts/abstract/UtilsReady.sol';

import '../interfaces/oracle/IYOracle.sol';
import '../interfaces/oracle/ISimpleOracle.sol';

contract YUnsafeOracleV1 is UtilsReady, IYOracle {
  address public override defaultOracle;

  mapping(address => address) public override pairOracle;

  constructor(address _defaultOracle) UtilsReady() {
    _setOracle(_defaultOracle);
  }

  function setPairOracle(address _pair, address _oracle) external override onlyGovernor {
    pairOracle[_pair] = _oracle;
  }

  function setDefaultOracle(address _defaultOracle) external override onlyGovernor {
    _setOracle(_defaultOracle);
  }

  function _setOracle(address _defaultOracle) internal {
    defaultOracle = _defaultOracle;
  }

  function getAmountOut(
    address _pair,
    address _tokenIn,
    uint256 _amountIn,
    address _tokenOut
  ) external view override returns (uint256 _amountOut) {
    if (pairOracle[_pair] != address(0)) return ISimpleOracle(pairOracle[_pair]).getAmountOut(_pair, _tokenIn, _amountIn, _tokenOut);
    return ISimpleOracle(defaultOracle).getAmountOut(_pair, _tokenIn, _amountIn, _tokenOut);
  }
}
