// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./GovStakingStorage.sol";

interface govERC20 {
    function mint(address to_, uint256 amount_) external;
}

interface ICommunityRewardsManager {
    function updateAllRewards(address account) external;

    function getAllRewards(address account) external;

    function resetSingleInactivMultiplier(
        uint256 totalRewardMultiplierSnapshot,
        address user
    ) external;

    function getStoreAddress() external view returns (address);
}

contract GovStakingV2 is Ownable, ReentrancyGuard, Pausable {
    uint256 public opt1 = 0;
    uint256 public opt2 = 1 weeks; // 1 week
    uint256 public opt3 = 2629746; // 1 month
    uint256 public opt4 = 15778476; // 6 month
    uint256 public opt5 = 31556952; // 1 year
    uint256 public opt6 = 94608000; // 3 years

    mapping(uint256 => uint256) public rewardRates; // locking period => rewardRates in wei per second per locked gogo

    IERC20 public gogo;
    govERC20 public govGogo;
    ICommunityRewardsManager public rewards;

    struct RewardRate {
        uint256 period;
        uint256 rate;
    }

    constructor(
        address gogoAddress,
        address govGogoAddress,
        address communityRewardsManager
    ) {
        gogo = IERC20(gogoAddress);
        govGogo = govERC20(govGogoAddress);
        rewards = ICommunityRewardsManager(communityRewardsManager);

        //rewardRates in wei per second per locked gogo
        rewardRates[opt1] = 1; // dummy
        rewardRates[opt2] = 1653439154;
        // reward for 1 week per second
        rewardRates[opt3] = 2471721604;
        // reward for 1 month per second
        rewardRates[opt4] = 4119536006;
        // reward for 6 month per second
        rewardRates[opt5] = 6971522471;
        // reward for 1 year per second
        rewardRates[opt6] = 8984441062;
        // reward for 3 years per second
    }

    event Enter(address indexed user, uint256 amount, uint256 extendingPeriod);
    event Leave(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event NewManager(address indexed newAddress);

    function enter(uint256 amount, uint256 extendingPeriod)
        external
        nonReentrant
        whenNotPaused
        returns (GovStakingStorage.UserInfo memory)
    {
        rewards.updateAllRewards(msg.sender);
        require(rewardRates[extendingPeriod] > 0, "wrong period");
        require(amount > 0 || extendingPeriod > 0, "invalid input");

        GovStakingStorage store = GovStakingStorage(rewards.getStoreAddress());
        gogo.transferFrom(msg.sender, address(store), amount);

        uint256 oldRate;
        GovStakingStorage.UserInfo memory user = store.getUserInformation(
            msg.sender
        );

        if (user.lockStart + user.lockPeriod <= block.timestamp) {
            // saving unclaimed community rewards
            rewards.resetSingleInactivMultiplier(
                store.getRewardMultiplier(),
                msg.sender
            );
        }

        (oldRate, user) = getUpdatedUserInformations(
            msg.sender,
            amount,
            extendingPeriod
        );

        storeUser(user);
        store.updateRewardRate(oldRate, user.rewardRate);
        store.addLockedGogo(amount);

        store.removeRewardMultiplier(msg.sender);
        store.addRewardMultiplier( // for gogo fee distribution
            msg.sender,
            user.rewardRate,
            60480000000,
            user.amount
        );

        emit Enter(msg.sender, amount, extendingPeriod);

        return user;
    }

    function getUpdatedUserInformations(
        address account,
        uint256 amount,
        uint256 extendingPeriod
    ) public view returns (uint256, GovStakingStorage.UserInfo memory) {
        GovStakingStorage store = GovStakingStorage(rewards.getStoreAddress());
        GovStakingStorage.UserInfo memory user = store.getUserInformation(
            account
        );

        uint256 oldRate = user.rewardRate;

        if (user.amount == 0) {
            // first lock of token. no calculation needed
            user.lockPeriod = extendingPeriod;
            user.lastClaimed = block.timestamp;
            user.rewardRate = rewardRates[extendingPeriod];
        } else {
            // already locked, but lockperiod is over
            if (user.lockStart + user.lockPeriod <= block.timestamp) {
                require(
                    extendingPeriod != 0,
                    "can't use the same period if it's over"
                );

                user.unclaimedAmount = getClaimAmount(
                    user,
                    user.lockStart + user.lockPeriod
                );
                user.lastClaimed = block.timestamp;
                user.rewardRate = rewardRates[extendingPeriod];
                user.lockPeriod = extendingPeriod;
            } else {
                if (
                    (user.lockStart + user.lockPeriod + extendingPeriod) >
                    (block.timestamp + opt6)
                ) {
                    extendingPeriod =
                        (block.timestamp + opt6) -
                        (user.lockStart + user.lockPeriod);
                }

                // already locked, but ongoing locking period
                user.unclaimedAmount = getClaimAmount(user, block.timestamp);
                user.lastClaimed = block.timestamp;
                uint256 rewardRate = getRewardForExtend(
                    account,
                    extendingPeriod,
                    amount,
                    oldRate
                );

                user.rewardRate = rewardRate;
                user.lockPeriod =
                    ((user.lockStart + user.lockPeriod) - block.timestamp) +
                    extendingPeriod;
            }
        }
        user.amount += amount;
        user.lockStart = block.timestamp;

        return (oldRate, user);
    }

    function leave() external nonReentrant whenNotPaused {
        rewards.updateAllRewards(msg.sender);
        GovStakingStorage store = GovStakingStorage(rewards.getStoreAddress());
        GovStakingStorage.UserInfo memory user = store.getUserInformation(
            msg.sender
        );
        require(
            block.timestamp >= user.lockPeriod + user.lockStart,
            "tokens are still locked"
        );
        _claim();
        rewards.getAllRewards(msg.sender);
        uint256 amount = user.amount;

        store.removeLockedGogo(amount);
        store.removeRewardRate(user.rewardRate);
        store.removeUser(msg.sender);

        store.transferGogo(msg.sender, amount);

        emit Leave(msg.sender, amount);
    }

    function _claim() internal {
        GovStakingStorage store = GovStakingStorage(rewards.getStoreAddress());
        GovStakingStorage.UserInfo memory user = store.getUserInformation(
            msg.sender
        );
        uint256 qualifiedUntil = (
            user.lockStart + (user.lockPeriod) < block.timestamp
                ? user.lockStart + user.lockPeriod
                : block.timestamp
        );

        uint256 toClaim = getClaimAmount(user, qualifiedUntil) +
            user.unclaimedAmount;

        user.unclaimedAmount = 0;
        user.lastClaimed = qualifiedUntil;

        storeUser(user);
        if (toClaim > 0) govGogo.mint(msg.sender, toClaim);

        emit Claim(msg.sender, toClaim);
    }

    function claim() external nonReentrant whenNotPaused {
        rewards.updateAllRewards(msg.sender);
        _claim();
    }

    function claimAll() external nonReentrant whenNotPaused {
        rewards.updateAllRewards(msg.sender);
        _claim();
        rewards.getAllRewards(msg.sender);
    }

    function getRewardForExtend(
        address account,
        uint256 extendingPeriod,
        uint256 amount,
        uint256 oldRate
    ) public view returns (uint256) {
        GovStakingStorage.UserInfo memory user = GovStakingStorage(
            rewards.getStoreAddress()
        ).getUserInformation(account);

        return
            extendingPeriod > 0
                ? calcExtendRate( // extend lock period (0 amount is possible)
                    user.lockPeriod,
                    user.lockPeriod - (block.timestamp - user.lockStart),
                    oldRate,
                    getRewardRate(user.lockPeriod + extendingPeriod)
                )
                : calcRate( // extend amount and not the period
                    user.amount,
                    amount,
                    oldRate,
                    getRewardRate(
                        user.lockStart + user.lockPeriod - block.timestamp
                    )
                );
    }

    function storeUser(GovStakingStorage.UserInfo memory user) internal {
        GovStakingStorage(rewards.getStoreAddress()).writeUser(
            msg.sender,
            user.amount,
            user.lockStart,
            user.lockPeriod,
            user.lastClaimed,
            user.unclaimedAmount,
            user.rewardRate
        );
    }

    function getRewardRate(uint256 period) internal view returns (uint256) {
        if (rewardRates[period] > 0) return rewardRates[period];
        if (period > opt6) return rewardRates[opt6]; // return maximum rate

        uint256 min = 0;
        uint256 max = 0;

        if (period >= opt1 && period <= opt2) {
            min = opt1;
            max = opt2;
        }
        if (period >= opt2 && period <= opt3) {
            min = opt2;
            max = opt3;
        }
        if (period >= opt3 && period <= opt4) {
            min = opt3;
            max = opt4;
        }
        if (period >= opt4 && period <= opt5) {
            min = opt4;
            max = opt5;
        }
        if (period >= opt5 && period <= opt6) {
            min = opt5;
            max = opt6;
        }

        return
            (((rewardRates[max] - rewardRates[min]) * (period - min)) /
                (max - min)) + rewardRates[min];
    }

    function earned() external view returns (uint256) {
        GovStakingStorage.UserInfo memory user = GovStakingStorage(
            rewards.getStoreAddress()
        ).getUserInformation(msg.sender);
        uint256 qualifiedUntil = (
            user.lockStart + (user.lockPeriod) < block.timestamp
                ? user.lockStart + user.lockPeriod
                : block.timestamp
        );

        return getClaimAmount(user, qualifiedUntil) + user.unclaimedAmount;
    }

    function getClaimAmount(
        GovStakingStorage.UserInfo memory user,
        uint256 timestamp
    ) internal pure returns (uint256) {
        return ((timestamp - user.lastClaimed) *
            (user.amount / 1e18) *
            (user.rewardRate));
    }

    function calcRate(
        uint256 amount1,
        uint256 amount2,
        uint256 rate1,
        uint256 rate2
    ) internal pure returns (uint256) {
        return ((rate1 * amount1) + (rate2 * amount2)) / (amount1 + amount2);
    }

    function calcExtendRate(
        uint256 t1,
        uint256 t2,
        uint256 r1,
        uint256 r2
    ) internal pure returns (uint256) {
        return ((r2 - r1) * ((t2 * 1e18) / t1)) / 1e18 + r1;
    }

    function setRewardRate(uint256 period, uint256 newRate) external onlyOwner {
        require(rewardRates[period] > 0, "wrong period");
        rewardRates[period] = newRate;
    }

    function setRewardRates(RewardRate[] memory rates) external onlyOwner {
        for (uint256 i = 0; i < rates.length; i++) {
            if (rewardRates[rates[i].period] > 0)
                rewardRates[rates[i].period] = rates[i].rate;
        }
    }

    function setCommunityManager(address newManager) external onlyOwner {
        rewards = ICommunityRewardsManager(newManager);
        emit NewManager(newManager);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
