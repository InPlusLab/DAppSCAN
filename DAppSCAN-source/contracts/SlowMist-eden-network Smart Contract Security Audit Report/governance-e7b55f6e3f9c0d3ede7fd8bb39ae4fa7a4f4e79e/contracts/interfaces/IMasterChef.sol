// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IMasterChef {
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SUSHIs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SUSHIs distribution occurs.
        uint256 accSushiPerShare; // Accumulated SUSHIs per share, times 1e12.
    }
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function poolInfo(uint256 _pid) external view returns (PoolInfo memory);
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);
    function updatePool(uint256 _pid) external;
    function sushiPerBlock() external view returns (uint256);
    function totalAllocPoint() external view returns (uint256);
    function getMultiplier(uint256 _from, uint256 _to) external view returns (uint256);
}