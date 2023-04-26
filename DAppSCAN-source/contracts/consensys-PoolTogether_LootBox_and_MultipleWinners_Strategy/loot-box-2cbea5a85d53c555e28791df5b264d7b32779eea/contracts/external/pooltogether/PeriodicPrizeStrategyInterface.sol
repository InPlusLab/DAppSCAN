// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.7.0;

/* solium-disable security/no-block-members */
interface PeriodicPrizeStrategyInterface {
  function prizePool() external view returns (address);
  function addExternalErc721Award(address _externalErc721, uint256[] calldata _tokenIds) external;
}
