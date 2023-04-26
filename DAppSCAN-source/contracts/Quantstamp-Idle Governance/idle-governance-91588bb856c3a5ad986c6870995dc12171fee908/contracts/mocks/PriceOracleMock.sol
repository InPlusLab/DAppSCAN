// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

contract PriceOracleMock {
  mapping (address => uint256) tokenAnswer;

  function setLatestAnswer(address token, uint256 _answer) external returns (uint256) {
    tokenAnswer[token] = _answer;
  }

  function getUnderlyingPrice(address token) external view returns (uint256) {
    return tokenAnswer[token];
  }
}
