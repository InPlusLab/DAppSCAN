pragma solidity 0.6.12;

interface ChainLinkOracle {
  function latestAnswer() external view returns (uint256);
}
