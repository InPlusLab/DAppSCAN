// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IERC20Metadata.sol";
import "./PoolVault.sol";
import "../base/BasicMetaTransaction.sol";


contract MutiRewardPool is Ownable, IERC20, BasicMetaTransaction {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.UintSet;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _callers;

    // Info of each user.
    struct UserInfo {
        EnumerableSet.UintSet stakingIds;
    }

    struct StakingInfo {
        uint256 pid;
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 token0RewardDebt; // Reward debt. See explanation below.
        uint256 token1RewardDebt; // Reward debt. See explanation below.
        uint256 time; //Pledge start time
    }

    struct StakingView {
        uint256 pid;
        uint256 stakingId;
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 token0UnclaimedRewards;
        uint256 token1UnclaimedRewards;
        uint256 time; //Pledge start time
        uint256 unlockTime;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 totalDeposit;
        uint256 duration;           //The duration of minimum pledge time.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Tokens to distribute per block.
        uint256 lastRewardBlock;  // Last block number that Tokens distribution occurs.
        uint256 token0AccRewardsPerShare; // Accumulated RewardTokens per share, times 1e12. See below.
        uint256 token1AccRewardsPerShare; // Accumulated RewardTokens per share, times 1e12. See below.
        uint256 token0AccAdditionalRewardsPerShare; // Accumulated Additional RewardTokens per share, times 1e12. See below.
        uint256 token1AccAdditionalRewardsPerShare; // Accumulated Additional RewardTokens per share, times 1e12. See below.
        uint256 token0AccDonateAmount;
        uint256 token1AccDonateAmount;
    }

    struct PoolView {
        uint256 pid;
        address lpToken;
        uint256 totalDeposit;
        uint256 duration; 
        uint256 allocPoint;       // How many allocation points assigned to this pool. Tokens to distribute per block.
        uint256 lastRewardBlock;  // Last block number that Tokens distribution occurs.
        uint256 token0AccRewardsPerShare; // Accumulated RewardTokens per share, times 1e12. See below.
        uint256 token1AccRewardsPerShare; // Accumulated RewardTokens per share, times 1e12. See below.
        uint256 token0AccAdditionalRewardsPerShare; // Accumulated Additional RewardTokens per share, times 1e12. See below.
        uint256 token1AccAdditionalRewardsPerShare; // Accumulated Additional RewardTokens per share, times 1e12. See below.
        uint256 token0AccDonateAmount;
        uint256 token1AccDonateAmount;
        uint256 token0RewardsPerBlock;
        uint256 token1RewardsPerBlock;
        uint256 token0AdditionalRewardPerBlock;
        uint256 token1AdditionalRewardPerBlock;
        string lpSymbol;
        string lpName;
        uint8 lpDecimals;
        string rewardToken0Symbol;
        string rewardToken0Name;
        uint8 rewardToken0Decimals;
        string rewardToken1Symbol;
        string rewardToken1Name;
        uint8 rewardToken1Decimals;
    }

    IERC20 public depositToken;
    IERC20 public rewardToken0;
    IERC20 public rewardToken1;
    PoolVault public poolVault;

    // uint256 public maxStaking;

    // tokens created per block.
    uint256 public token0RewardPerBlock;
    uint256 public token1RewardPerBlock;

    // Additional bonus per block
    uint256 public token0AdditionalRewardPerBlock;
    uint256 public token1AdditionalRewardPerBlock;

    // Additional bonus end block
    uint256 public token0AdditionalRewardEndBlock;
    uint256 public token1AdditionalRewardEndBlock;

    // Bonus muliplier for early makers.
    uint256 public BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) private userInfo;
    mapping (uint256 => StakingInfo) public stakingInfo;

    uint256 private lastStakingId;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 private totalAllocPoint = 0;


    // The block number when mining starts.
    uint256 public startBlock;
    // The block number when mining ends.
    uint256 public bonusEndBlock;

    event Deposit(address indexed user, uint256 pid, uint256 stakingId, uint256 amount);
    event Withdraw(address indexed user, uint256 pid, uint256 stakingId, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 pid, uint256 stakingId, uint256 amount);
    event Harvest(address indexed user, uint256 pid, uint256 stakingId, uint256 reward0Amount, uint256 reward1Amount);
    event Donate(address indexed user, uint256 pid, address donteToken, uint256 donateAmount, uint256 realAmount);

    constructor(
        IERC20 _depositToken,
        IERC20 _rewardToken0,
        IERC20 _rewardToken1,
        uint256 _token0RewardPerBlock,
        uint256 _token1RewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        depositToken = _depositToken;
        rewardToken0 = _rewardToken0;
        rewardToken1 = _rewardToken1;
        token0RewardPerBlock = _token0RewardPerBlock;
        token1RewardPerBlock = _token1RewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        poolVault = new PoolVault();
        poolVault.approve(address(depositToken));
    }

    // function stopReward() public onlyOwner {
    //     bonusEndBlock = block.number;
    // }


    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER);
        }
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        massUpdatePools();
        BONUS_MULTIPLIER = multiplierNumber;
    }
    //SWC-135-Code With No Effects: L178-L200
    function addPool(
        uint256 _stakingDuration,
        uint256 _allocPoint
    ) public onlyOwner {
        massUpdatePools();

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: depositToken,
            totalDeposit: 0,
            duration: _stakingDuration,
            allocPoint: _allocPoint,
            lastRewardBlock: block.number > startBlock? block.number: startBlock,
            token0AccRewardsPerShare: 0,
            token1AccRewardsPerShare: 0,
            token0AccAdditionalRewardsPerShare: 0,
            token1AccAdditionalRewardsPerShare: 0,
            token0AccDonateAmount: 0,
            token1AccDonateAmount: 0
        }));

        totalAllocPoint = totalAllocPoint.add(_allocPoint);
    }

    // View function to see token0 pending Reward on frontend.
    function token0PendingReward(uint256 _stakingId) public view returns (uint256) {
        
        StakingInfo storage user = stakingInfo[_stakingId];
        PoolInfo storage pool = poolInfo[user.pid];
        uint256 lpSupply = pool.totalDeposit;

        if (user.amount == 0) {
            return 0;
        }

        uint256 amount;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            
            uint256 accRewardsPerShare = pool.token0AccRewardsPerShare;
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(token0RewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardsPerShare = accRewardsPerShare.add(tokenReward.mul(1e12).div(lpSupply));
            amount = user.amount.mul(accRewardsPerShare);
            
            uint256 endBlock = block.number > token0AdditionalRewardEndBlock? token0AdditionalRewardEndBlock : block.number;
            uint256 accAdditionalRewardsPerShare = pool.token0AccAdditionalRewardsPerShare;
            if (endBlock > pool.lastRewardBlock) {
                uint256 additionalMultiplier = getMultiplier(pool.lastRewardBlock, endBlock);
                uint256 additionalTokenReward = additionalMultiplier.mul(token0AdditionalRewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                accAdditionalRewardsPerShare = accAdditionalRewardsPerShare.add(additionalTokenReward.mul(1e12).div(lpSupply));
            }
            amount = amount.add(user.amount.mul(accAdditionalRewardsPerShare));
        }

        return amount.div(1e12).sub(user.token0RewardDebt);
    }

    // View function to see token1 pending Reward on frontend.
    function token1PendingReward(uint256 _stakingId) public view returns (uint256) {
        StakingInfo storage user = stakingInfo[_stakingId];
        PoolInfo storage pool = poolInfo[user.pid];
        uint256 lpSupply = pool.totalDeposit;

        if (user.amount == 0) {
            return 0;
        }

        uint256 amount;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            
            uint256 accRewardsPerShare = pool.token1AccRewardsPerShare;
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(token1RewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardsPerShare = accRewardsPerShare.add(tokenReward.mul(1e12).div(lpSupply));
            amount = user.amount.mul(accRewardsPerShare);
            
            uint256 endBlock = block.number > token1AdditionalRewardEndBlock? token1AdditionalRewardEndBlock : block.number;
            uint256 accAdditionalRewardsPerShare = pool.token1AccAdditionalRewardsPerShare;
            if (endBlock > pool.lastRewardBlock) {
                uint256 additionalMultiplier = getMultiplier(pool.lastRewardBlock, endBlock);
                uint256 additionalTokenReward = additionalMultiplier.mul(token1AdditionalRewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                accAdditionalRewardsPerShare = accAdditionalRewardsPerShare.add(additionalTokenReward.mul(1e12).div(lpSupply));
            }
            amount = amount.add(user.amount.mul(accAdditionalRewardsPerShare));
        }

        return amount.div(1e12).sub(user.token1RewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.totalDeposit;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);

        uint256 token0Reward = multiplier.mul(token0RewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.token0AccRewardsPerShare = pool.token0AccRewardsPerShare.add(token0Reward.mul(1e12).div(lpSupply));
        {
            uint256 endBlock = block.number > token0AdditionalRewardEndBlock? token0AdditionalRewardEndBlock : block.number;
            if (endBlock > pool.lastRewardBlock) {
                uint256 additionalMultiplier = getMultiplier(pool.lastRewardBlock, endBlock);
                uint256 additionalTokenReward = additionalMultiplier.mul(token0AdditionalRewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                pool.token0AccAdditionalRewardsPerShare = pool.token0AccAdditionalRewardsPerShare.add(additionalTokenReward.mul(1e12).div(lpSupply));
            }

            if (block.number >= token0AdditionalRewardEndBlock) {
                token0AdditionalRewardPerBlock = 0;
            }
        }
        
        uint256 token1Reward = multiplier.mul(token1RewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.token1AccRewardsPerShare = pool.token1AccRewardsPerShare.add(token1Reward.mul(1e12).div(lpSupply));
        {
            uint256 endBlock = block.number > token1AdditionalRewardEndBlock? token1AdditionalRewardEndBlock : block.number;
            if (endBlock > pool.lastRewardBlock) {
                uint256 additionalMultiplier = getMultiplier(pool.lastRewardBlock, endBlock);
                uint256 additionalTokenReward = additionalMultiplier.mul(token1AdditionalRewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                pool.token1AccAdditionalRewardsPerShare = pool.token1AccAdditionalRewardsPerShare.add(additionalTokenReward.mul(1e12).div(lpSupply));
            }

            if (block.number >= token1AdditionalRewardEndBlock) {
                token1AdditionalRewardPerBlock = 0;
            }
        }

        pool.lastRewardBlock = block.number;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Stake tokens to Pool
    function deposit(uint256 pid, uint256 _amount) public {
        require(_amount > 0, "bad amount");

        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[msgSender()];

        // require (_amount.add(user.amount) <= maxStaking, 'exceed max stake');

        updatePool(pid);

        uint256 oldBal = pool.lpToken.balanceOf(address(poolVault));
        pool.lpToken.safeTransferFrom(address(msgSender()), address(poolVault), _amount);
        _amount = pool.lpToken.balanceOf(address(poolVault)).sub(oldBal);

        lastStakingId++;
        pool.totalDeposit = pool.totalDeposit.add(_amount);

        stakingInfo[lastStakingId] = StakingInfo({
            pid: pid,
            amount: _amount,
            token0RewardDebt: _amount.mul(pool.token0AccRewardsPerShare).add(_amount.mul(pool.token0AccAdditionalRewardsPerShare)).div(1e12),
            token1RewardDebt: _amount.mul(pool.token1AccRewardsPerShare).add(_amount.mul(pool.token1AccAdditionalRewardsPerShare)).div(1e12),
            time: block.timestamp
        });
        user.stakingIds.add(lastStakingId);

        emit Deposit(msgSender(), pid, lastStakingId, _amount);
        emit Transfer(address(0), msgSender(), _amount);
    }

    function harvestAll() public {
        UserInfo storage user = userInfo[msgSender()];

        uint256 len = user.stakingIds.length();

        for(uint256 i = 0; i < len; ++i) {
            harvest(user.stakingIds.at(i));
        }
    }

    function harvestPool(uint256 pid) public {
        UserInfo storage user = userInfo[msgSender()];

        uint256 len = user.stakingIds.length();

        for(uint256 i = 0; i < len; ++i) {
            uint256 id = user.stakingIds.at(i);
            if (stakingInfo[id].pid != pid) {
                continue;
            }
            harvest(id);
        }
    }

    function harvest(uint256 _stakingId) public {
        
        UserInfo storage user = userInfo[msgSender()];
        require(user.stakingIds.contains(_stakingId), "not the staking owner");
        StakingInfo storage staking = stakingInfo[_stakingId];
        PoolInfo storage pool = poolInfo[staking.pid];

        updatePool(staking.pid);

        uint256 reward0;
        uint256 reward1;
        if (staking.amount > 0) {
            {
                uint256 pending = staking.amount.mul(pool.token0AccRewardsPerShare).add(staking.amount.mul(pool.token0AccAdditionalRewardsPerShare)).div(1e12).sub(staking.token0RewardDebt);
                if(pending > 0) {
                    uint256 bal = rewardToken0.balanceOf(address(this));
                    if(bal >= pending) {
                        reward0 = pending;
                    } else {
                        reward0 = bal;
                    }
                }
            }
            
            {
                uint256 pending = staking.amount.mul(pool.token1AccRewardsPerShare).add(staking.amount.mul(pool.token1AccAdditionalRewardsPerShare)).div(1e12).sub(staking.token1RewardDebt);
                if(pending > 0) {
                    uint256 bal = rewardToken1.balanceOf(address(this));
                    if(bal >= pending) {
                        reward1 = pending;
                    } else {
                        reward1 = bal;
                    }
                }
            }
        }

        staking.token0RewardDebt = staking.amount.mul(pool.token0AccRewardsPerShare).add(staking.amount.mul(pool.token0AccAdditionalRewardsPerShare)).div(1e12);
        staking.token1RewardDebt = staking.amount.mul(pool.token1AccRewardsPerShare).add(staking.amount.mul(pool.token1AccAdditionalRewardsPerShare)).div(1e12);

        if (reward0 > 0) {
            rewardToken0.safeTransfer(address(msgSender()), reward0);
        }

         if (reward1 > 0) {
            rewardToken1.safeTransfer(address(msgSender()), reward1);
        }

        emit Harvest(msgSender(), staking.pid, _stakingId, reward0, reward1);
    }

    // Withdraw tokens from STAKING.
    function withdraw(uint256 _stakingId) public {
        UserInfo storage user = userInfo[msgSender()];
        require(user.stakingIds.contains(_stakingId), "not the staking owner");
        StakingInfo storage staking = stakingInfo[_stakingId];
        PoolInfo storage pool = poolInfo[staking.pid];

        require(block.timestamp.sub(staking.time) >= pool.duration, "not time");

        harvest(_stakingId);

        uint256 _amount = staking.amount;
        staking.amount = 0;
        pool.totalDeposit = pool.totalDeposit.sub(_amount);
        pool.lpToken.safeTransferFrom(address(poolVault), address(msgSender()), _amount);
        
        staking.token0RewardDebt = _amount.mul(pool.token0AccRewardsPerShare).add(_amount.mul(pool.token0AccAdditionalRewardsPerShare)).div(1e12);
        staking.token1RewardDebt = _amount.mul(pool.token1AccRewardsPerShare).add(_amount.mul(pool.token1AccAdditionalRewardsPerShare)).div(1e12);

        user.stakingIds.remove(_stakingId);

        emit Withdraw(msgSender(), staking.pid, _stakingId, _amount);
        emit Transfer(msgSender(), address(0), _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _stakingId) public {
        UserInfo storage user = userInfo[msgSender()];
        require(user.stakingIds.contains(_stakingId), "not the staking owner");
        StakingInfo storage staking = stakingInfo[_stakingId];
        PoolInfo storage pool = poolInfo[staking.pid];
        require(block.number.sub(staking.time) >= pool.duration, "not time");

        uint256 amount = staking.amount;
        
        if(pool.totalDeposit >= staking.amount) {
            pool.totalDeposit = pool.totalDeposit.sub(staking.amount);
        } else {
            pool.totalDeposit = 0;
        }
        staking.amount = 0;
        staking.token0RewardDebt = 0;
        staking.token1RewardDebt = 0;

        user.stakingIds.remove(_stakingId);

        pool.lpToken.safeTransferFrom(address(poolVault), address(msgSender()), amount);

        emit EmergencyWithdraw(msgSender(),  staking.pid, _stakingId, amount);
        emit Transfer(msgSender(), address(0), amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdrawToken0(uint256 _amount) public onlyOwner {
        require(_amount <= rewardToken0.balanceOf(address(this)), 'not enough token');
        rewardToken0.safeTransfer(address(msgSender()), _amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdrawToken1(uint256 _amount) public onlyOwner {
        require(_amount <= rewardToken1.balanceOf(address(this)), 'not enough token');
        rewardToken1.safeTransfer(address(msgSender()), _amount);
    }

    function totalStaking(address account) public view returns(uint256 amount) {
        UserInfo storage user = userInfo[account];
        uint ln = user.stakingIds.length();

        for (uint i = 0; i < ln; ++i) {
            amount = amount.add(stakingInfo[user.stakingIds.at(i)].amount);
        }
    }

    function donate(IERC20 token, uint256 donateAmount) public {
        require(token == rewardToken0 || token == rewardToken1, "not support token");

        uint256 oldBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msgSender(), address(this), donateAmount);
        uint256 realAmount = IERC20(token).balanceOf(address(this)) - oldBal;

        bool isToken0 = token == rewardToken0 ? true : false;
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);

            PoolInfo storage pool = poolInfo[pid];
            if(pool.allocPoint == 0) {
                continue;
            }

            if(pool.totalDeposit == 0) {
                continue;
            }

            uint256 tokenReward = realAmount.mul(1e12).mul(pool.allocPoint).div(totalAllocPoint);
            if (isToken0) {
                pool.token0AccRewardsPerShare = pool.token0AccRewardsPerShare.add(tokenReward.div(pool.totalDeposit));
                pool.token0AccDonateAmount = pool.token0AccDonateAmount.add(tokenReward);
            } else {
                pool.token1AccRewardsPerShare = pool.token1AccRewardsPerShare.add(tokenReward.div(pool.totalDeposit));
                pool.token1AccDonateAmount = pool.token1AccDonateAmount.add(tokenReward);
            }
            emit Donate(msgSender(), pid, address(token), tokenReward.div(1e12), tokenReward.div(1e12));
        }
    }

    function addAdditionalRewards(IERC20 token, uint256 amount, uint256 rewardsBlocks) public onlyCaller {
        require(token == rewardToken0 || token == rewardToken1, "not support token");

        massUpdatePools();

        uint256 oldBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msgSender(), address(this), amount);
        uint256 realAmount = IERC20(token).balanceOf(address(this)).sub(oldBal);

        if (token == rewardToken0) {
            uint256 remainingBlocks = token0AdditionalRewardEndBlock > block.number ? token0AdditionalRewardEndBlock.sub(block.number) : 0;
            uint256 remainingBal = token0AdditionalRewardPerBlock.mul(remainingBlocks);

            if(remainingBal > 0) {
                rewardsBlocks = rewardsBlocks.add(remainingBlocks);
            }
            remainingBal = remainingBal.add(realAmount);

            token0AdditionalRewardPerBlock = remainingBal.div(rewardsBlocks);

            if(block.number >= startBlock) {
                token0AdditionalRewardEndBlock = block.number.add(rewardsBlocks);
            } else {
                token0AdditionalRewardEndBlock = startBlock.add(rewardsBlocks);
            }
        } else {
            uint256 remainingBlocks = token1AdditionalRewardEndBlock > block.number ? token1AdditionalRewardEndBlock.sub(block.number) : 0;
            uint256 remainingBal = token1AdditionalRewardPerBlock.mul(remainingBlocks);

            if(remainingBal > 0) {
                rewardsBlocks = rewardsBlocks.add(remainingBlocks);
            }
            remainingBal = remainingBal.add(realAmount);

            token1AdditionalRewardPerBlock = remainingBal.div(rewardsBlocks);

            if(block.number >= startBlock) {
                token1AdditionalRewardEndBlock = block.number.add(rewardsBlocks);
            } else {
                token1AdditionalRewardEndBlock = startBlock.add(rewardsBlocks);
            }
        }
    }

    function getBaseInfo() public view 
    returns (
        address depositToken_, 
        address rewardToken0_, 
        address rewardToken1_, 
        uint256 token0RewardPerBlock_,
        uint256 token1RewardPerBlock_,
        uint256 token0AdditionalRewardPerBlock_,
        uint256 token1AdditionalRewardPerBlock_,
        uint256 token0AdditionalRewardEndBlock_,
        uint256 token1AdditionalRewardEndBlock_,
        uint256 totalAllocPoint_,
        uint256 startBlock_,
        uint256 bonusEndBlock_
    ) {
        depositToken_ = address(depositToken);
        rewardToken0_ = address(rewardToken0);
        rewardToken1_ = address(rewardToken1);
        token0RewardPerBlock_ = token0RewardPerBlock;
        token1RewardPerBlock_ = token1RewardPerBlock;
        token0AdditionalRewardPerBlock_ = token0AdditionalRewardPerBlock;
        token1AdditionalRewardPerBlock_ = token1AdditionalRewardPerBlock;
        token0AdditionalRewardEndBlock_ = token0AdditionalRewardEndBlock;
        token1AdditionalRewardEndBlock_ = token1AdditionalRewardEndBlock;
        totalAllocPoint_ = totalAllocPoint;
        startBlock_ = startBlock;
        bonusEndBlock_ = bonusEndBlock;
    }

    function getPoolView(uint256 pid) public view returns(PoolView memory) {
        require(pid < poolInfo.length, "MutiRewardPool: pid out of range");

        PoolInfo memory pool = poolInfo[pid];

        string memory symbol = IERC20Metadata(address(pool.lpToken)).symbol();
        string memory name = IERC20Metadata(address(pool.lpToken)).name();
        uint8 decimals = IERC20Metadata(address(pool.lpToken)).decimals();

        uint256 rewardsPerBlock0 = pool.allocPoint.mul(token0RewardPerBlock).div(totalAllocPoint);
        uint256 rewardsPerBlock1 = pool.allocPoint.mul(token1RewardPerBlock).div(totalAllocPoint);

        uint256 additionalRewardsPerBlock0 = pool.allocPoint.mul(token0AdditionalRewardPerBlock).div(totalAllocPoint);
        uint256 additionalRewardsPerBlock1 = pool.allocPoint.mul(token1AdditionalRewardPerBlock).div(totalAllocPoint);

        return
            PoolView({
                pid: pid,
                lpToken: address(pool.lpToken),
                totalDeposit: pool.totalDeposit,
                duration: pool.duration,
                allocPoint: pool.allocPoint,
                lastRewardBlock: pool.lastRewardBlock,
                token0AccRewardsPerShare: pool.token0AccRewardsPerShare,
                token1AccRewardsPerShare: pool.token1AccRewardsPerShare,
                token0AccAdditionalRewardsPerShare: pool.token0AccAdditionalRewardsPerShare,
                token1AccAdditionalRewardsPerShare: pool.token1AccAdditionalRewardsPerShare,
                token0AccDonateAmount: pool.token0AccDonateAmount,
                token1AccDonateAmount: pool.token1AccDonateAmount,
                token0RewardsPerBlock: rewardsPerBlock0,
                token1RewardsPerBlock: rewardsPerBlock1,
                token0AdditionalRewardPerBlock: additionalRewardsPerBlock0,
                token1AdditionalRewardPerBlock: additionalRewardsPerBlock1,
                lpSymbol: symbol,
                lpName: name,
                lpDecimals: decimals,
                rewardToken0Symbol: IERC20Metadata(address(rewardToken0)).symbol(),
                rewardToken0Name: IERC20Metadata(address(rewardToken0)).name(),
                rewardToken0Decimals: IERC20Metadata(address(rewardToken0)).decimals(),
                rewardToken1Symbol: IERC20Metadata(address(rewardToken1)).symbol(),
                rewardToken1Name: IERC20Metadata(address(rewardToken1)).name(),
                rewardToken1Decimals: IERC20Metadata(address(rewardToken1)).decimals()
            });
    }

    function getAllPoolViews() external view returns (PoolView[] memory) {
        PoolView[] memory views = new PoolView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            views[i] = getPoolView(i);
        }
        return views;
    }

    function getStakingView(uint256 stakingId) public view returns(StakingView memory) {
        StakingInfo memory staking = stakingInfo[stakingId];

        uint256 token0UnclaimedRewards = token0PendingReward(stakingId);
        uint256 token1UnclaimedRewards = token1PendingReward(stakingId);

        return StakingView({
            pid: staking.pid,
            stakingId: stakingId,
            amount: staking.amount,
            token0UnclaimedRewards: token0UnclaimedRewards,
            token1UnclaimedRewards: token1UnclaimedRewards,
            time: staking.time,
            unlockTime: poolInfo[staking.pid].duration.add(staking.time)
        });

    }

    function getStakingViews(address account) public view returns(StakingView[] memory) {
        UserInfo storage user = userInfo[account];

        uint256 len = user.stakingIds.length();

        StakingView[] memory views = new StakingView[](len);

        for (uint i = 0; i < len; ++i) {
            views[i] = getStakingView(user.stakingIds.at(i));
        }
        return views;
    }

    /******************************   ERC20   ******************************/

    function name() public view virtual returns (string memory) {
        return string( abi.encodePacked( "Staked ", IERC20Metadata(address(depositToken)).symbol() ));
    }

    function symbol() public view virtual returns (string memory) {
        return string( abi.encodePacked( "ve", IERC20Metadata(address(depositToken)).symbol() ));
    }

    function decimals() public view virtual returns (uint8) {
        return IERC20Metadata(address(depositToken)).decimals();
    }

    function totalSupply() public view override returns (uint256) {
        uint256 totalDeposit;
        for(uint i = 0; i < poolInfo.length; ++i) {
            totalDeposit = totalDeposit.add(poolInfo[i].totalDeposit.mul(poolInfo[i].allocPoint));
        }
        return totalDeposit;
    }

    function balanceOf(address account) public view override returns (uint256) {
        
        UserInfo storage user = userInfo[account];
        uint ln = user.stakingIds.length();

        uint256 bal;
        for (uint i = 0; i < ln; ++i) {
            StakingInfo memory staking = stakingInfo[user.stakingIds.at(i)];
            bal = bal.add(staking.amount.mul(poolInfo[staking.pid].allocPoint));
        }

        return bal;
    }

    function transfer(address, uint256) public override returns (bool) {
        revert("can not allow transfer");
    }

    function allowance(address, address) public view override returns (uint256) {
        return 0;
    }

    function approve(address, uint256) public override returns (bool) {
        revert("can not allow approve");
    }

    function transferFrom(address, address, uint256) public override returns (bool) {
        revert("can not allow transfer");
    }


    /******************************   Caller   ******************************/

    modifier onlyCaller() {
        require(isCaller(msgSender()), "Treasury: not the caller");
        _;
    }

    function addCaller(address _newCaller) public onlyOwner returns (bool) {
        require(_newCaller != address(0), "MutiRewardPool: address is zero");
        return EnumerableSet.add(_callers, _newCaller);
    }

    function delCaller(address _delCaller) public onlyOwner returns (bool) {
        require(_delCaller != address(0), "MutiRewardPool: address is zero");
        return EnumerableSet.remove(_callers, _delCaller);
    }

    function getCallerLength() public view returns (uint256) {
        return EnumerableSet.length(_callers);
    }

    function isCaller(address _caller) public view returns (bool) {
        return EnumerableSet.contains(_callers, _caller);
    }

    function getCaller(uint256 _index) public view returns (address) {
        require(_index <= getCallerLength() - 1, "MutiRewardPool: index out of bounds");
        return EnumerableSet.at(_callers, _index);
    }
}