// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGovernance {
    struct RewardScheduleEntry {
        uint64 startTime;
        uint64 epochDuration;
        uint128 rewardsPerEpoch; 
    }

    function rewardCollector(address producer) external view returns (address);
    function blockProducer(address producer) external view returns (bool);
    function rewardScheduleEntries() external view returns (uint256);
    function rewardScheduleEntry(uint256 index) external view returns (RewardScheduleEntry memory);

    event BlockProducerAdded(address indexed producer);
    event BlockProducerRemoved(address indexed producer);
    event BlockProducerRewardCollectorChanged(address indexed producer, address indexed collector);
    event RewardScheduleChanged();
}
