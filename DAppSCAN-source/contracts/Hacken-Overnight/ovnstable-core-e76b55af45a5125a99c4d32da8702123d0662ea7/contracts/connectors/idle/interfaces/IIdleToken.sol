// SPDX-License-Identifier: MIT
pragma solidity >=0.5 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156.sol";

interface IIdleToken is IERC20 {
    function token() external view returns (address underlying);
    function govTokens(uint256) external view returns (address govToken);
    function userAvgPrices(address) external view returns (uint256 avgPrice);
    function mintIdleToken(uint256 _amount, bool _skipWholeRebalance, address _referral) external returns (uint256 mintedTokens);
    function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);
    function redeemInterestBearingTokens(uint256 _amount) external;
    function rebalance() external returns (bool);
    function tokenPrice() external view returns (uint256 price);
    function getAPRs() external view returns (address[] memory addresses, uint256[] memory aprs);
    function getAvgAPR() external view returns (uint256 avgApr);
    function getGovTokensAmounts(address _usr) external view returns (uint256[] memory _amounts);
    function flashLoanFee() external view returns (uint256 fee);
    function flashFee(address _token, uint256 _amount) external view returns (uint256);
    function maxFlashLoan(address _token) external view returns (uint256);
    function flashLoan(IERC3156FlashBorrower _receiver, address _token, uint256 _amount, bytes calldata _params) external returns (bool);
    function getAllocations() external view returns (uint256[] memory);
    function getGovTokens() external view returns (address[] memory);
    function getAllAvailableTokens() external view returns (address[] memory);
    function getProtocolTokenToGov(address _protocolToken) external view returns (address);
    function tokenPriceWithFee(address user) external view returns (uint256 priceWFee);
}