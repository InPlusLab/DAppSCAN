// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
    function onReward(uint256, address, address, uint256, uint256) external;
    function pendingTokens(uint256, address, uint256) external view returns (IERC20[] memory, uint256[] memory);
}
