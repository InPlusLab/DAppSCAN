// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./LiquidityMiningManager.sol";
import "./TimeLockPool.sol";


/// @dev reader contract to easily fetch all relevant info for an account
contract View {

    struct Data {
        uint256 pendingRewards;
        Pool[] pools;
        Pool escrowPool;
        uint256 totalWeight;
    }

    struct Deposit {
        uint256 amount;
        uint64 start;
        uint64 end;
        uint256 multiplier;
    }

    struct Pool {
        address poolAddress;
        uint256 totalPoolShares;
        address depositToken;
        uint256 accountPendingRewards;
        uint256 accountClaimedRewards;
        uint256 accountTotalDeposit;
        uint256 accountPoolShares;
        uint256 weight;
        Deposit[] deposits;
    }

    LiquidityMiningManager public immutable liquidityMiningManager;
    TimeLockPool public immutable escrowPool;

    constructor(address _liquidityMiningManager, address _escrowPool) {
        liquidityMiningManager = LiquidityMiningManager(_liquidityMiningManager);
        escrowPool = TimeLockPool(_escrowPool);
    }
    //SWC-DoS With Block Gas Limit: L45-L83
    function fetchData(address _account) external view returns (Data memory result) {
        uint256 rewardPerSecond = liquidityMiningManager.rewardPerSecond();
        uint256 lastDistribution = liquidityMiningManager.lastDistribution();
        uint256 pendingRewards = rewardPerSecond * (block.timestamp - lastDistribution);

        result.totalWeight = liquidityMiningManager.totalWeight();

        LiquidityMiningManager.Pool[] memory pools = liquidityMiningManager.getPools();

        result.pools = new Pool[](pools.length);

        for(uint256 i = 0; i < pools.length; i ++) {

            TimeLockPool poolContract = TimeLockPool(address(pools[i].poolContract));

            result.pools[i] = Pool({
                poolAddress: address(pools[i].poolContract),
                totalPoolShares: poolContract.totalSupply(),
                depositToken: address(poolContract.depositToken()),
                accountPendingRewards: poolContract.withdrawableRewardsOf(_account),
                accountClaimedRewards: poolContract.withdrawnRewardsOf(_account),
                accountTotalDeposit: poolContract.getTotalDeposit(_account),
                accountPoolShares: poolContract.balanceOf(_account),
                weight: pools[i].weight,
                deposits: new Deposit[](poolContract.getDepositsOfLength(_account))
            });

            TimeLockPool.Deposit[] memory deposits = poolContract.getDepositsOf(_account);

            for(uint256 j = 0; j < result.pools[i].deposits.length; j ++) {
                TimeLockPool.Deposit memory deposit = deposits[j];
                result.pools[i].deposits[j] = Deposit({
                    amount: deposit.amount,
                    start: deposit.start,
                    end: deposit.end,
                    multiplier: poolContract.getMultiplier(deposit.end - deposit.start)
                });
            }
        }

        result.escrowPool = Pool({
            poolAddress: address(escrowPool),
            totalPoolShares: escrowPool.totalSupply(),
            depositToken: address(escrowPool.depositToken()),
            accountPendingRewards: escrowPool.withdrawableRewardsOf(_account),
            accountClaimedRewards: escrowPool.withdrawnRewardsOf(_account),
            accountTotalDeposit: escrowPool.getTotalDeposit(_account),
            accountPoolShares: escrowPool.balanceOf(_account),
            weight: 0,
            deposits: new Deposit[](escrowPool.getDepositsOfLength(_account))
        });

        TimeLockPool.Deposit[] memory deposits = escrowPool.getDepositsOf(_account);

        for(uint256 j = 0; j < result.escrowPool.deposits.length; j ++) {
            TimeLockPool.Deposit memory deposit = deposits[j];
            result.escrowPool.deposits[j] = Deposit({
                amount: deposit.amount,
                start: deposit.start,
                end: deposit.end,
                multiplier: escrowPool.getMultiplier(deposit.end - deposit.start)
            });
        } 

    }

}