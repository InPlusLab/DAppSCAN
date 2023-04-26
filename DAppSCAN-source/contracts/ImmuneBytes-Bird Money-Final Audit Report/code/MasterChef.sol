// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity 0.6.12;

// MasterChef is the master of RewardToken. He can make RewardToken and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once REWARD_TOKEN is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 unstakeTime; // user can unstake LP tokens at this time to get reward
        //
        // We do some fancy math here. Basically, any point in time, the amount of REWARD_TOKENs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardTokenPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardTokenPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. REWARD_TOKENs to distribute per block.
        uint256 lastRewardBlock; // Last block number that REWARD_TOKENs distribution occurs.
        uint256 accRewardTokenPerShare; // Accumulated REWARD_TOKENs per share, times 1e12. See below.
    }

    // The REWARD_TOKEN TOKEN!
    IERC20 public rewardToken;
    // Dev address.
    // address public devaddr;
    // Block number when bonus REWARD_TOKEN period ends.
    uint256 public bonusEndBlock;
    // REWARD_TOKEN tokens created per block.
    uint256 public rewardTokenPerBlock;
    // Bonus muliplier for early rewardToken makers.
    uint256 public constant BONUS_MULTIPLIER = 10;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The block number when REWARD_TOKEN distribution starts.
    uint256 public startRewardBlock;

    // The block number when REWARD_TOKEN distribution stops.
    uint256 public endRewardBlock;

    //user can get reward and unstake after this time only.
    uint256 public unstakeFrozenTime = 72 hours;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        IERC20 _rewardToken,
        // address _devaddr,
        uint256 _rewardTokenPerBlock,
        uint256 _startRewardBlock,
        uint256 _endRewardBlock,
        uint256 _bonusEndBlock
    ) public {
        rewardToken = _rewardToken;
        rewardTokenPerBlock = _rewardTokenPerBlock;
        startRewardBlock = _startRewardBlock;
        endRewardBlock = _endRewardBlock;
        bonusEndBlock = _bonusEndBlock;
    }

    function setAll(
        IERC20 _rewardToken,
        uint256 _rewardTokenPerBlock,
        uint256 _startRewardBlock,
        uint256 _endRewardBlock,
        uint256 _bonusEndBlock,
        uint256 _unstakeFrozenTime
    ) public onlyOwner {
        rewardToken = _rewardToken;
        rewardTokenPerBlock = _rewardTokenPerBlock;
        startRewardBlock = _startRewardBlock;
        endRewardBlock = _endRewardBlock;
        bonusEndBlock = _bonusEndBlock;
        unstakeFrozenTime = _unstakeFrozenTime;
    }

    function setRewardToken(IERC20 _rewardToken) public onlyOwner {
        rewardToken = _rewardToken;
    }

    function setUnstakeFrozenTime(uint256 _unstakeFrozenTime) public onlyOwner {
        unstakeFrozenTime = _unstakeFrozenTime;
    }

    function setRewardTokenPerBlock(uint256 _rewardTokenPerBlock)
        public
        onlyOwner
    {
        rewardTokenPerBlock = _rewardTokenPerBlock;
    }

    function setStartRewardBlock(uint256 _startRewardBlock) public onlyOwner {
        startRewardBlock = _startRewardBlock;
    }

    function setEndRewardBlock(uint256 _endRewardBlock) public onlyOwner {
        endRewardBlock = _endRewardBlock;
    }

    function setBonusEndBlock(uint256 _bonusEndBlock) public onlyOwner {
        bonusEndBlock = _bonusEndBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > startRewardBlock ? block.number : startRewardBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardTokenPerShare: 0
            })
        );
    }

    // Update the given pool's REWARD_TOKEN allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return
                bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEndBlock)
                );
        }
    }

    // View function to see pending REWARD_TOKENs on frontend.
    function pendingRewardToken(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardTokenPerShare = pool.accRewardTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 rewardTokenReward =
                multiplier.mul(rewardTokenPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accRewardTokenPerShare = accRewardTokenPerShare.add(
                rewardTokenReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.amount.mul(accRewardTokenPerShare).div(1e12).sub(
                user.rewardDebt
            );
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 rewardTokenReward =
            multiplier.mul(rewardTokenPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        //rewardToken.mint(devaddr, rewardTokenReward.div(10));
        //rewardToken.mint(address(this), rewardTokenReward);
        pool.accRewardTokenPerShare = pool.accRewardTokenPerShare.add(
            rewardTokenReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for REWARD_TOKEN allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accRewardTokenPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            if (now > user.unstakeTime)
                safeRewardTokenTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        user.unstakeTime = now + unstakeFrozenTime;
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accRewardTokenPerShare).div(
            1e12
        );
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        if (now > user.unstakeTime) {
            updatePool(_pid);
            uint256 pending =
                user.amount.mul(pool.accRewardTokenPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            safeRewardTokenTransfer(msg.sender, pending);
            user.amount = user.amount.sub(_amount);
            user.rewardDebt = user.amount.mul(pool.accRewardTokenPerShare).div(
                1e12
            );
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            emit Withdraw(msg.sender, _pid, _amount);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe rewardToken transfer function, just in case if rounding error causes pool to not have enough REWARD_TOKENs.
    function safeRewardTokenTransfer(address _to, uint256 _amount) internal {
        if (
            block.number >= startRewardBlock && block.number <= endRewardBlock
        ) {
            uint256 rewardTokenBal = rewardToken.balanceOf(address(this));
            if (_amount > rewardTokenBal) {
                rewardToken.transfer(_to, rewardTokenBal);
            } else {
                rewardToken.transfer(_to, _amount);
            }
        }
    }

    // Update dev address by the previous dev.
    // function dev(address _devaddr) public {
    //     require(msg.sender == devaddr, "dev: wut?");
    //     devaddr = _devaddr;
    // }

    IMigratorChef public migrator;

    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    function depositRewardTokens(uint256 _amount) public onlyOwner {
        rewardToken.transferFrom(msg.sender, address(this), _amount);
    }

    function withdrawRewardTokens(uint256 _amount) public onlyOwner {
        rewardToken.transfer(msg.sender, _amount);
    }
}

interface IMigratorChef {
    function migrate(IERC20 token) external returns (IERC20);
}
