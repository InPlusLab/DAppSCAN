//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IVaultStrategy {
    function vault() external view returns (address);
    function want() external view returns (IERC20);
    function deposit() external;
    function withdraw(uint256) external returns (uint256);
    function balanceOf() external view returns (uint256);
    function balanceOfWant() external view returns (uint256);
    function balanceOfPool() external view returns (uint256);
    function harvest(uint256 feeAmountOutMin, uint256 lpAmountOutMin) external;
    function panic() external;
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}