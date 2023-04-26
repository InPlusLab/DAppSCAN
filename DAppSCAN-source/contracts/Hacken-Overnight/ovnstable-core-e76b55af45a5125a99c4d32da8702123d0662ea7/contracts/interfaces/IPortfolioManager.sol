// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPortfolioManager {
    function deposit(IERC20 _token, uint256 _amount) external;

    function withdraw(IERC20 _token, uint256 _amount) external returns (uint256);

    function withdrawProportional(uint256 _proportion, uint256 _proportionDenominator) external returns (address[] memory);

    function balanceOnReward() external;

    function claimRewards() external;
}
