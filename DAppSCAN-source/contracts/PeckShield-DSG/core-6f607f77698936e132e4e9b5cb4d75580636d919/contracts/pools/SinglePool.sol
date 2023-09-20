// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract SinglePool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Tokens to distribute per block.
        uint256 lastRewardBlock;  // Last block number that Tokens distribution occurs.
        uint256 accRewardsPerShare; // Accumulated RewardTokens per share, times 1e18. See below.
    }

    IERC20 public depositToken;
    IERC20 public rewardToken;

    // uint256 public maxStaking;

    // tokens created per block.
    uint256 public rewardPerBlock;

    // Bonus muliplier for early makers.
    uint256 public BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) public userInfo;
    // Total amount pledged by users
    uint256 public totalDeposit;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 private totalAllocPoint = 0;
    // The block number when mining starts.
    uint256 public startBlock;
    // The block number when mining ends.
    uint256 public bonusEndBlock;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        IERC20 _depositToken,
        IERC20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        depositToken = _depositToken;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _depositToken,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accRewardsPerShare: 0
        }));

        totalAllocPoint = 1000;
        // maxStaking = 50000000000000000000;

    }

    function stopReward() public onlyOwner {
        bonusEndBlock = block.number;
    }


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
        BONUS_MULTIPLIER = multiplierNumber;
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        uint256 accRewardsPerShare = pool.accRewardsPerShare;
        uint256 lpSupply = totalDeposit;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardsPerShare = accRewardsPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accRewardsPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = totalDeposit;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accRewardsPerShare = pool.accRewardsPerShare.add(tokenReward.mul(1e18).div(lpSupply));
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
    function deposit(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];

        // require (_amount.add(user.amount) <= maxStaking, 'exceed max stake');

        updatePool(0);
        
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e18).sub(user.rewardDebt);
            if(pending > 0) {
                uint256 bal = rewardToken.balanceOf(address(this));
                if(bal >= pending) {
                    rewardToken.safeTransfer(address(msg.sender), pending);
                } else {
                    rewardToken.safeTransfer(address(msg.sender), bal);
                }
            }
        }
        if(_amount > 0) {
            uint256 oldBal = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)).sub(oldBal);

            user.amount = user.amount.add(_amount);
            totalDeposit = totalDeposit.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e18);

        emit Deposit(msg.sender, _amount);
    }

    // Withdraw tokens from STAKING.
    function withdraw(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e18).sub(user.rewardDebt);
        if(pending > 0) {
            uint256 bal = rewardToken.balanceOf(address(this));
            if(bal >= pending) {
                rewardToken.safeTransfer(address(msg.sender), pending);
            } else {
                rewardToken.safeTransfer(address(msg.sender), bal);
            }
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            totalDeposit = totalDeposit.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e18);

        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    //SWC-107-Reentrancy: L202-L214
    function emergencyWithdraw() public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        if(totalDeposit >= user.amount) {
            totalDeposit = totalDeposit.sub(user.amount);
        } else {
            totalDeposit = 0;
        }
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) public onlyOwner {
        require(_amount <= rewardToken.balanceOf(address(this)), 'not enough token');
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

}