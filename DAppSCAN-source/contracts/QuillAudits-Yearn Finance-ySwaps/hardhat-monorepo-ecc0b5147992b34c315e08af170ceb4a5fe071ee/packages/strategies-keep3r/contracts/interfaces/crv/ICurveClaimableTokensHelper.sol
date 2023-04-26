// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ICurveClaimableTokensHelper {
  function claimable_tokens(address _gauge, address _voter) external view returns (uint256 _claimableTokens);
}
