// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@yearn/contract-utils/contracts/abstract/UtilsReady.sol';

import '../interfaces/oracle/ISimpleOracle.sol';
import '../interfaces/keep3r/IKeep3rV2OracleFactory.sol';

contract Keep3rV2OracleFactoryWrapper is UtilsReady, ISimpleOracle {
  address public immutable keep3rV2OracleFactory;

  constructor(address _keep3rV2OracleFactory) UtilsReady() {
    keep3rV2OracleFactory = _keep3rV2OracleFactory;
  }

  function getAmountOut(
    address _pair,
    address _tokenIn,
    uint256 _amountIn,
    address _tokenOut
  ) external view override returns (uint256 _amountOut) {
    (_amountOut, ) = IKeep3rV2OracleFactory(keep3rV2OracleFactory).current(_pair, _tokenIn, _amountIn, _tokenOut);
  }
}
