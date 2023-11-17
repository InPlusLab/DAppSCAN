pragma solidity 0.8.7; //SPDX-License-Identifier: UNLICENSED

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMasterChef {
    event LuckyPerBlockUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event PoolAdded(IERC20 indexed lpToken,uint256 indexed allocPoint,uint256 harvestTimestamp, uint256 farmStartTimestamp);
    event PoolSet(uint256 indexed pid,uint256 indexed allocPoint,uint256 harvestTimestampInUnix, uint256 farmStartTimestampInUnix);
    event DevAddressSet(address indexed oldDevAddress,address indexed _devAddress);
    function add(uint256 _allocPoint, IERC20 _lpToken, uint256 _harvestIntervalInMinutes,uint256 _farmStartIntervalInMinutes) external;
    function set(uint256 _pid, uint256 _allocPoint, uint256 _harvestIntervalInMinutes,uint256 _farmStartIntervalInMinutes) external;
    function setDevAddress(address _devAddress) external;
    function updateLuckyPerBlock(uint256 _luckyPerBlock) external;
}