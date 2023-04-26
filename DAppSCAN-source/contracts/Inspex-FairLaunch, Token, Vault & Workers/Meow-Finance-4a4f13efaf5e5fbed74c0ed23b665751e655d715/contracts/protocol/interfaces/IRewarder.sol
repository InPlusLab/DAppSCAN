pragma solidity 0.6.6;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
  function pendingTokens(
    uint256 pid,
    address user,
    uint256 sushiAmount
  ) external view returns (IERC20[] memory, uint256[] memory);

  function rewardPerSecond() external view returns (uint256);
}
