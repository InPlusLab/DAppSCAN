// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IKeep3rV1Helper {
  function quote(uint256 eth) external view returns (uint256);

  function getFastGas() external view returns (uint256);

  function bonds(address keeper) external view returns (uint256);

  function getQuoteLimit(uint256 gasUsed) external view returns (uint256);

  function getQuoteLimitFor(address origin, uint256 gasUsed) external view returns (uint256);
}
