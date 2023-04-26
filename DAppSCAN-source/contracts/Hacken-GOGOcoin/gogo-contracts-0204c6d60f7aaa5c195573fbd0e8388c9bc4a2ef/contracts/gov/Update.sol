// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "./GovStakingStorage.sol";
//import "./CommunityRewards.sol";
import "./CommunityRewardsV2.sol";

contract Update is Ownable {
    GovStakingStorage store;
    CommunityRewardsV2 rewards;
    CommunityRewardsV2 rewards2;

    constructor(
        address _store,
        address _rewards,
        address _rewards2
    ) {
        store = GovStakingStorage(_store);
        rewards = CommunityRewardsV2(_rewards);
        rewards2 = CommunityRewardsV2(_rewards2);
    }

    function updateData(uint256 from, uint256 to) public onlyOwner {
        for (uint256 x = from; from < to; x++) {
            address account = store.userList(x);
            GovStakingStorage.UserInfo memory info = store.getUserInformation(
                account
            );
            rewards.updateReward(account);
            uint256 earned = rewards.earned(account);
            rewards2.setPreviouslyUnclaimedForSingleUser(account, earned);
            store.removeRewardMultiplier(account);
            store.addRewardMultiplier(
                account,
                info.rewardRate,
                60480000000,
                info.amount
            );
        }
    }
}
