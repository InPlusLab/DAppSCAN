// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

interface IIdleTokenHelper {
  function getMintingPrice(address idleYieldToken) view external returns (uint256 mintingPrice);
  function getRedeemPrice(address idleYieldToken) view external returns (uint256 redeemPrice);
  function getRedeemPrice(address idleYieldToken, address user) view external returns (uint256 redeemPrice);
}
