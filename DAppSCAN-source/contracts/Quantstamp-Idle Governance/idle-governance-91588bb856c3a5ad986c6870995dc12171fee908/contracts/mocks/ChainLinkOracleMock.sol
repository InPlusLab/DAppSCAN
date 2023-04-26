// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

contract ChainLinkOracleMock {
  uint256 public answer;

  function setLatestAnswer(uint256 _answer) external returns (uint256) {
    answer = _answer;
  }

  function latestAnswer() external view returns (uint256) {
    return answer;
  }
}
