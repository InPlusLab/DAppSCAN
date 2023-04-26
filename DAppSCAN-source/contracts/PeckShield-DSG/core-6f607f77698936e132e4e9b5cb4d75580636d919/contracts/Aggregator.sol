// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./pools/LiquidityPool.sol";
import "./pools/DepositPool.sol";
import "./pools/TradingPool.sol";
import "./governance/Treasury.sol";
import "./governance/InitializableOwner.sol";

contract Aggregator is InitializableOwner{
    struct UserMiningInfo {
        uint256 userAmount;
        uint256 userUnclaimedReward;
        uint256 userAccReward;
        uint8 poolType;
        uint256 pid;
        address pair;
        uint256 totalAmount;
        uint256 rewardsPerBlock;
        uint256 allocPoint;
        address token0;
        string name0;
        string symbol0;
        uint8 decimals0;
        address token1;
        string name1;
        string symbol1;
        uint8 decimals1;
    }

    struct TreasuryInfo {
        uint256 nftBonusRatio;
        uint256 totalFee;
        uint256 nftBonusAmount;
        uint256 totalDistributedFee;
        uint256 totalBurnedDSG;
        uint256 totalRepurchasedUSDT;
    }

    LiquidityPool liquidityPool;
    DepositPool depositPool;
    TradingPool tradingPool;
    Treasury treasury;
    address public DSG;

    constructor() public {
    }

    function initialize(
        address _liquidityPool,
        address _depositPool,
        address _tradingPool,
        address _treasury,
        address _dsg
    ) public {
        super._initialize();

        liquidityPool = LiquidityPool(_liquidityPool);
        depositPool = DepositPool(_depositPool);
        tradingPool = TradingPool(_tradingPool);
        treasury = Treasury(_treasury);
        DSG = _dsg;
    }

    function getCirculationSupply() public view returns (uint256 supply) {
        supply =
            IERC20(DSG).totalSupply();
    }

    function getTreasuryInfo() public view returns (TreasuryInfo memory) {
        return
            TreasuryInfo({
                nftBonusRatio: treasury.nftBonusRatio(),
                totalFee: treasury.totalFee(),
                nftBonusAmount: treasury.nftBonusAmount(),
                totalDistributedFee: treasury.totalDistributedFee(),
                totalBurnedDSG: treasury.totalBurnedDSG(),
                totalRepurchasedUSDT: treasury.totalRepurchasedUSDT()
            });
    }

    function getUserMiningInfos(address _account) public view returns (UserMiningInfo[] memory) {
        UserMiningInfo[] memory infos = new UserMiningInfo[](40);

        uint256 index = 0;

        for (uint256 i = 0; i < liquidityPool.getPoolLength(); i++) {
            LiquidityPool.PoolView memory lpPV = liquidityPool.getPoolView(i);
            LiquidityPool.UserView memory lpUV = liquidityPool.getUserView(lpPV.lpToken, _account);
            uint256 unclaimedRewards = liquidityPool.pendingRewards(i, _account);
            if (unclaimedRewards > 0 || lpUV.accRewardAmount > 0) {
                infos[index] = UserMiningInfo({
                    userAmount: lpUV.stakedAmount,
                    userUnclaimedReward: unclaimedRewards,
                    userAccReward: lpUV.accRewardAmount,
                    poolType: 1,
                    pid: i,
                    pair: lpPV.lpToken,
                    totalAmount: lpPV.totalAmount,
                    rewardsPerBlock: lpPV.rewardsPerBlock,
                    allocPoint: lpPV.allocPoint,
                    token0: lpPV.token0,
                    name0: lpPV.name0,
                    symbol0: lpPV.symbol0,
                    decimals0: lpPV.decimals0,
                    token1: lpPV.token1,
                    name1: lpPV.name1,
                    symbol1: lpPV.symbol1,
                    decimals1: lpPV.decimals1
                });
                index++;
            }
        }

        for (uint256 i = 0; i < tradingPool.getPoolLength(); i++) {
            TradingPool.PoolView memory tPV = tradingPool.getPoolView(i);
            TradingPool.UserView memory tUV = tradingPool.getUserView(tPV.pair, _account);
            uint256 unclaimedRewards = tradingPool.pendingRewards(i, _account);
            if (unclaimedRewards > 0 || tUV.accRewardAmount > 0) {
                infos[index] = UserMiningInfo({
                    userAmount: tUV.quantity,
                    userUnclaimedReward: tUV.unclaimedRewards,
                    userAccReward: tUV.accRewardAmount,
                    poolType: 2,
                    pid: i,
                    pair: tPV.pair,
                    totalAmount: tPV.quantity,
                    rewardsPerBlock: tPV.rewardsPerBlock,
                    allocPoint: tPV.allocPoint,
                    token0: tPV.token0,
                    name0: tPV.name0,
                    symbol0: tPV.symbol0,
                    decimals0: tPV.decimals0,
                    token1: tPV.token1,
                    name1: tPV.name1,
                    symbol1: tPV.symbol1,
                    decimals1: tPV.decimals1
                });
                index++;
            }
        }

        for (uint256 i = 0; i < depositPool.getPoolLength(); i++) {
            DepositPool.PoolView memory dPV = depositPool.getPoolView(i);
            DepositPool.UserView memory dUV = depositPool.getUserView(dPV.token, _account);
            uint256 unclaimedRewards = depositPool.pendingRewards(i, _account);
            if (unclaimedRewards > 0 || dUV.accRewardAmount > 0) {
                infos[index] = UserMiningInfo({
                    userAmount: dUV.stakedAmount,
                    userUnclaimedReward: dUV.unclaimedRewards,
                    userAccReward: dUV.accRewardAmount,
                    poolType: 3,
                    pid: i,
                    pair: address(0),
                    totalAmount: dPV.totalAmount,
                    rewardsPerBlock: dPV.rewardsPerBlock,
                    allocPoint: dPV.allocPoint,
                    token0: dPV.token,
                    name0: dPV.name,
                    symbol0: dPV.symbol,
                    decimals0: dPV.decimals,
                    token1: address(0),
                    name1: "",
                    symbol1: "",
                    decimals1: 0
                });
                index++;
            }
        }

        UserMiningInfo[] memory userInfos = new UserMiningInfo[](index);
        for (uint256 i = 0; i < index; i++) {
            userInfos[i] = infos[i];
        }

        return userInfos;
    }

    function harvestFarm() public {
        liquidityPool.harvestAll();
        depositPool.harvestAll();
    }

    function harvestAll() public {
        liquidityPool.harvestAll();
        depositPool.harvestAll();
        tradingPool.harvestAll();
    }
}
