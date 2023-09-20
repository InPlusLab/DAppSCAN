// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// SWC-135-Code With No Effects: L7
import "hardhat/console.sol";

contract GovStakingStorage is Ownable {
    IERC20 public gogo;
    uint256 totalLockedGogo;
    uint256 totalRewardRates;
    uint256 totalRewardMultiplier;

    struct UserInfo {
        uint256 amount; // current locked amount
        uint256 lockStart; // for governance staking
        uint256 lockPeriod; // for governance staking
        uint256 lastClaimed; // govGoGo
        uint256 unclaimedAmount; // govGoGo
        uint256 rewardRate; // for governance staking
        uint256 rewardMultiplier; // for gogo reward fee distribution
        uint256 userRewardPerTokenPaid; // for gogo reward fee distribution
        uint256 index;
    }

    mapping(address => UserInfo) public userInfo;
    address[] public userList;
    mapping(address => bool) public allowed;

    modifier isAllowed() {
        require(allowed[msg.sender], "sender is not allowed to write");
        _;
    }

    constructor(address gogoAddress) {
        gogo = IERC20(gogoAddress);
    }

    function addLockedGogo(uint256 amount) external isAllowed {
        totalLockedGogo += amount;
    }

    function removeLockedGogo(uint256 amount) external isAllowed {
        totalLockedGogo -= amount;
    }

    function addRewardRate(uint256 amount) external isAllowed {
        totalRewardRates += amount;
    }

    function removeRewardRate(uint256 amount) external isAllowed {
        totalRewardRates -= amount;
    }

    function updateRewardRate(uint256 oldRate, uint256 newRate)
        external
        isAllowed
    {
        totalRewardRates = totalRewardRates + newRate - oldRate;
    }

    function writeUser(
        address user,
        uint256 amount,
        uint256 lockStart,
        uint256 lockPeriod,
        uint256 lastClaimed,
        uint256 unclaimedAmount, //gov
        uint256 rewardRate
    ) external isAllowed {
        UserInfo storage info = userInfo[user];
        info.amount = amount;
        info.lockStart = lockStart;
        info.lockPeriod = lockPeriod;
        info.lastClaimed = lastClaimed;
        info.unclaimedAmount = unclaimedAmount;
        info.rewardRate = rewardRate;
        if (userInfo[user].index == 0) {
            info.index = userList.length;
            userList.push(user);
        }
        userInfo[user] = info;
    }

    function removeUser(address user) external isAllowed {
        require(userInfo[user].index != 0, "user does not exist");
        if (userList.length > 1) {
            address lastAddress = userList[userList.length - 1];
            uint256 oldIndex = userInfo[user].index;
            userList[oldIndex] = lastAddress;
            userInfo[lastAddress].index = oldIndex;
        }
        userList.pop();
        totalRewardMultiplier -= userInfo[user].rewardMultiplier;
        delete userInfo[user];
    }

    function transferGogo(address to, uint256 amount) external isAllowed {
        gogo.transfer(to, amount);
    }

    function updateRewardMultiplier(
        address user,
        uint256 oldRate,
        uint256 newRate,
        uint256 passedTime,
        uint256 oldLockPeriod,
        uint256 newLockPeriod,
        uint256 oldAmount,
        uint256 newAmount
    ) external isAllowed {
        UserInfo storage info = userInfo[user];
        uint256 toRemove = ((((oldLockPeriod - passedTime) / 1 weeks) *
            oldRate) * oldAmount) / 100000;
        uint256 toAdd = (((newLockPeriod / 1 weeks) * newRate) * newAmount) /
            100000;
        info.rewardMultiplier = info.rewardMultiplier + toAdd - toRemove;
        totalRewardMultiplier = totalRewardMultiplier + toAdd - toRemove;
    }

    function addRewardMultiplier(
        address user,
        uint256 rate,
        uint256 period,
        uint256 amount
    ) external isAllowed {
        UserInfo storage info = userInfo[user];
        info.rewardMultiplier +=
            ((((rate * period) / 1 weeks) * amount)) /
            100000;
        totalRewardMultiplier +=
            ((((rate * period) / 1 weeks) * amount)) /
            100000;
    }

    function removeRewardMultiplier(address user) public isAllowed {
        UserInfo storage info = userInfo[user];
        totalRewardMultiplier -= info.rewardMultiplier;
        info.rewardMultiplier = 0;
    }

    function addUserRewardPerTokenPaid(address user, uint256 amount)
        external
        isAllowed
    {
        UserInfo storage info = userInfo[user];
        info.userRewardPerTokenPaid += amount;
    }

    // views
    function getTotalLockedGogo() external view returns (uint256) {
        return totalLockedGogo;
    }

    function getTotalRewardRates() external view returns (uint256) {
        return totalRewardRates;
    }

    function getUserMultiplier(address user) public view returns (uint256) {
        return userInfo[user].rewardMultiplier;
    }

    function getUserInformation(address user)
        external
        view
        returns (UserInfo memory)
    {
        return userInfo[user];
    }

    function getUserListLength() external view returns (uint256) {
        return userList.length;
    }

    function getAmount(address user) public view returns (uint256) {
        return userInfo[user].amount;
    }

    function getUserRewardPerTokenPaid(address user)
        public
        view
        returns (uint256)
    {
        return userInfo[user].userRewardPerTokenPaid;
    }

    function setUserRewardPerTokenPaid(address user, uint256 amount)
        external
        isAllowed
    {
        UserInfo storage info = userInfo[user];
        info.userRewardPerTokenPaid = amount;
    }

    /**
     * userList[to] is not included in the returned array
     */
    function getUserInfoByIndex(uint256 from, uint256 to)
        external
        view
        returns (UserInfo[] memory)
    {
        uint256 to_ = to > userList.length ? userList.length : to;
        UserInfo[] memory result = new UserInfo[](to - from);
        for (uint256 i = 0; i < to_ - from; i++) {
            result[i] = userInfo[userList[i + from]];
        }
        return result;
    }

    function getRewardMultiplier() public view returns (uint256) {
        return totalRewardMultiplier;
    }

    function getLockDate(address user) public view returns (uint256) {
        return (userInfo[user].lockStart + userInfo[user].lockPeriod);
    }

    // owner only
    function setWriteAllowance(address to, bool flag) external onlyOwner {
        allowed[to] = flag;
    }

    function emergencyWithdraw() external onlyOwner {
        gogo.transfer(owner(), gogo.balanceOf(address(this)));
    }
}
