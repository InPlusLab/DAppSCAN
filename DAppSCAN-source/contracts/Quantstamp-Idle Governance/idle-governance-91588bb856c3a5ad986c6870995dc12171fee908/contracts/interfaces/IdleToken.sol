pragma solidity 0.6.12;

interface IdleToken {
  function totalSupply() external view returns (uint256);
  function tokenPrice() external view returns (uint256 price);
  function token() external view returns (address);
  function getAvgAPR() external view returns (uint256 apr);
  function balanceOf(address) external view returns (uint256 apr);
  function getAPRs() external view returns (address[] memory addresses, uint256[] memory aprs);
  function mintIdleToken(uint256 _amount, bool _skipRebalance, address _referral) external returns (uint256 mintedTokens);
  function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);
  function redeemInterestBearingTokens(uint256 _amount) external;
  function rebalance() external returns (bool);
}
