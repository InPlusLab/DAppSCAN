// SPDX-License-Identifier: Apache-2.0
/**
 * @title: Idle Token interface
 * @author: Idle Labs Inc., idle.finance
 */
pragma solidity 0.8.4;

import "./IERC20Detailed.sol";

interface IIdleToken is IERC20Detailed {
  function tokenPrice() external view returns (uint256 price);
  function tokenDecimals() external view returns (uint256);
  function token() external view returns (address);
  function getAPRs() external view returns (address[] memory addresses, uint256[] memory aprs);
  function mintIdleToken(uint256 _amount, bool _skipRebalance, address _referral) external returns (uint256 mintedTokens);
  function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);
  function redeemInterestBearingTokens(uint256 _amount) external;
  function rebalance() external returns (bool);
  function getAvgAPR() external view returns (uint256);
  function govTokens(uint256 index) external view returns (address);
  function getGovTokensAmounts(address _usr) external view returns (uint256[] memory _amounts);
  function getAllocations() external view returns (uint256[] memory);
  function getGovTokens() external view returns (address[] memory);
  function getAllAvailableTokens() external view returns (address[] memory);
  function getProtocolTokenToGov(address _protocolToken) external view returns (address);
  function oracle() external view returns (address);
  function owner() external view returns (address);
  function rebalancer() external view returns (address);
  function protocolWrappers(address) external view returns (address);
  function tokenPriceWithFee(address user) external view returns (uint256 priceWFee);
  function fee() external view returns (uint256);
}
