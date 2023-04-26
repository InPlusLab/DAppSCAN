// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.4;

import "./StakingRewardsLP.sol";

contract PoolManager is Ownable {
    using SafeMath for uint256;

    struct PoolInfo {
        // StakingRewardsLP contract address
        address poolAddress;
        address stakingTokenAddress;
        address rewardsTokenAddress;
    }

    mapping(address => bool) public poolExists;
    mapping(address => uint256) public poolIndices;
    PoolInfo[] public pools;

    event PoolAdded(
        address poolAddress,
        address stakingTokenAddress,
        address rewardsTokenAddress
    );
    event PoolRemoved(address poolAddress);
    event AllPoolsRemoved();
    event RewardsClaimedWithoutLoss(uint256 countPoolsClaimed);

    function addPool(address poolAddress) public onlyOwner {
        require(!poolExists[poolAddress], "This pool already exists");

        require(
            StakingRewardsLP(poolAddress).poolManager() == address(this),
            "PoolManager is not set in the staking contract"
        );

        StakingRewardsLP _pool = StakingRewardsLP(poolAddress);
        IERC20 stakingToken = _pool.stakingToken();
        IERC20 rewardsToken = _pool.rewardsToken();

        PoolInfo memory _poolInfo;
        _poolInfo.poolAddress = poolAddress;
        _poolInfo.stakingTokenAddress = address(stakingToken);
        _poolInfo.rewardsTokenAddress = address(rewardsToken);

        poolIndices[poolAddress] = pools.length;
        pools.push(_poolInfo);
        poolExists[poolAddress] = true;

        emit PoolAdded(
            poolAddress,
            _poolInfo.stakingTokenAddress,
            _poolInfo.rewardsTokenAddress
        );
    }

    function removePool(address poolAddress) public onlyOwner {
        require(
            poolExists[poolAddress],
            "Can't remove what's not there. Pool doesn't exist"
        );

        uint256 idx = poolIndices[poolAddress];
        poolExists[poolAddress] = false;
        pools[idx] = pools[pools.length - 1];
        pools.pop();

        // delete mapping to array for the element being removed
        delete poolIndices[poolAddress];

        // if the element being removed was not the last one in array (so that other element actually moved)
        if (idx != pools.length) {
            // update mapping for the moved element
            poolIndices[pools[idx].poolAddress] = idx;
        }

        emit PoolRemoved(poolAddress);
    }

    function getPoolsCount() public view returns (uint256) {
        return pools.length;
    }

    function earnedAcrossPools(address account) public view returns (uint256) {
        uint256 totalEarned = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            totalEarned = totalEarned.add(
                StakingRewardsLP(pools[i].poolAddress).earned(account)
            );
        }
        return totalEarned;
    }

    function totalRewardsClaimableWithoutLoss(address account)
        public
        view
        returns (uint256)
    {
        uint256 totalClaimable = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            totalClaimable = totalClaimable.add(
                StakingRewardsLP(pools[i].poolAddress)
                .rewardsClaimableWithoutLoss(account)
            );
        }
        return totalClaimable;
    }

    function removeAllPools() public onlyOwner {
        for (uint256 i = 0; i < pools.length; i++) {
            poolIndices[pools[i].poolAddress] = 0; // same as 'delete poolIndices[pools[i].poolAddress]'
            poolExists[pools[i].poolAddress] = false;
        }
        delete pools;
        emit AllPoolsRemoved();
    }

    function claimAllRewards() public {
        uint256 poolsClaimed = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            StakingRewardsLP pool = StakingRewardsLP(pools[i].poolAddress);
            if (pool.rewardsClaimableWithoutLoss(msg.sender) > 0) {
                pool.getRewardFor(msg.sender);
                poolsClaimed += 1;
            }
        }
        emit RewardsClaimedWithoutLoss(poolsClaimed);
    }
}
