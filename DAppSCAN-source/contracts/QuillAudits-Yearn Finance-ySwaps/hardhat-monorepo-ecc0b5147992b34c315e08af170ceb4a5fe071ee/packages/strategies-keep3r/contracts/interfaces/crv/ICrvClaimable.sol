// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ICrvClaimable {
  function claimable_tokens(address _address) external returns (uint256 _amount);
}
