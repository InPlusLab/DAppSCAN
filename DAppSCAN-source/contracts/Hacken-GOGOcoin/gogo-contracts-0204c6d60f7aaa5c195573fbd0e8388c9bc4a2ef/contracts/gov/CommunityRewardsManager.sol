// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface ICommunityRewards {
    function updateReward(address account) external;

    function getRewardFor(address user) external;

    function resetInactiveMultipliers(
        uint256 totalRewardMultiplierSnapshot,
        address[] memory users
    ) external;
}

interface IGovStakingv2 {
    function paused() external returns (bool);
}

contract CommunityRewardsManager is Ownable {
    address private BLOCKER = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

    address[] public communityRewardsList;
    mapping(address => uint256) public listIndexes;

    mapping(address => bool) allowed;

    address public store;
    address public govStaking;

    modifier isAllowed() {
        require(allowed[msg.sender], "msg is not allowed");
        _;
    }

    event AllowanceSet(address indexed account, bool allowance);
    event NewGovStaking(address indexed newAddress);
    event NewStore(address indexed newAddress);

    constructor(address _store) {
        store = _store;
        communityRewardsList.push(BLOCKER);
        // to avoid index 0 for other address
    }

    function updateAllRewards(address account) external {
        for (uint256 i = 1; i < communityRewardsList.length; i++) {
            ICommunityRewards(communityRewardsList[i]).updateReward(account);
        }
    }

    function getAllRewards(address account) external isAllowed {
        for (uint256 i = 1; i < communityRewardsList.length; i++) {
            ICommunityRewards(communityRewardsList[i]).getRewardFor(account);
        }
    }

    function resetSingleInactivMultiplier(
        uint256 totalRewardMultiplierSnapshot,
        address user
    ) external isAllowed {
        address[] memory users = new address[](1);
        users[0] = user;
        _resetInactiveMultipliers(totalRewardMultiplierSnapshot, users);
    }

    function resetInactiveMultipliers(
        uint256 totalRewardMultiplierSnapshot,
        address[] memory users
    ) external isAllowed {
        require(
            IGovStakingv2(govStaking).paused(),
            "GovStaking contract must be paused"
        );
        _resetInactiveMultipliers(totalRewardMultiplierSnapshot, users);
    }

    function _resetInactiveMultipliers(
        uint256 totalRewardMultiplierSnapshot,
        address[] memory users
    ) internal {
        for (uint256 i = 1; i < communityRewardsList.length; i++) {
            ICommunityRewards(communityRewardsList[i]).resetInactiveMultipliers(
                totalRewardMultiplierSnapshot,
                users
            );
        }
    }

    function getStoreAddress() external view returns (address) {
        return store;
    }

    // owner functions

    function addRewardContract(address newContract) external onlyOwner {
        require(
            listIndexes[newContract] == 0 && newContract != BLOCKER, // blocker needed for 0 check
            "address already added"
        );
        listIndexes[newContract] = communityRewardsList.length;
        communityRewardsList.push(newContract);
        emit AllowanceSet(newContract, true);
    }

    function removeRewardContract(address oldContract) external onlyOwner {
        require(
            listIndexes[oldContract] > 0 && oldContract != BLOCKER,
            "unknown address"
        );
        if (communityRewardsList.length > 2) {
            // length 1 = blocker address
            uint256 oldIndex = listIndexes[oldContract];
            listIndexes[
                communityRewardsList[communityRewardsList.length - 1]
            ] = oldIndex;
            communityRewardsList[oldIndex] = communityRewardsList[
                communityRewardsList.length - 1
            ];
        }
        communityRewardsList.pop();
        delete listIndexes[oldContract];
        emit AllowanceSet(oldContract, false);
    }

    function setAllowance(address allow, bool flag) external onlyOwner {
        allowed[allow] = flag;
    }

    function setStore(address newStore) external onlyOwner {
        store = newStore;
        emit NewStore(newStore);
    }

    function setGovStaking(address newGov) external onlyOwner {
        govStaking = newGov;
        emit NewGovStaking(newGov);
    }
}
