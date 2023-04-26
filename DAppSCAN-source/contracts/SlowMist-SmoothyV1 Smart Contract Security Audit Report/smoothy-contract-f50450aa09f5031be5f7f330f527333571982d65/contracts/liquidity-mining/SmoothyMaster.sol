// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;


import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/utils/EnumerableSet.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/utils/Pausable.sol";
import "openzeppelin-solidity/contracts/math/Math.sol";
import "./SMTYToken.sol";


// SmoothyMaster is the master of Smoothy. He can make Smoothy and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SMTY is sufficiently
// distributed and the community can show to govern itself.
contract SmoothyMaster is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 smtyRewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SMTYs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSMTYPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSMTYPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool.
        uint256 lastRewardBlock;  // Last block number that SMTYs distribution occurs.
        uint256 accSMTYPerShare; // Accumulated SMTYs per share, times 1e12. See below.
        address rewardedToken;
    }

    // The SMTY TOKEN!
    SMTYToken public smty;
    // Dev address.
    address public devAddr;
    // SMTY tokens created per block.
    uint256 public genesisSmtyPerBlock;
    // Bonus multiplier for early smty makers.
    uint256 public constant GENESIS_EPOCH_BONUS_MULTIPLIER = 2;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SMTY mining starts.
    uint256 public startBlock;
    // The number of blocks per epoch.
    uint256 public blocksInGenesisEpoch;


    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        SMTYToken _smty,
        address _devAddr,
        uint256 _genesisSmtyPerBlock,
        uint256 _startBlock,
        uint256 _blocksInGenesisEpoch
    ) public {
        smty = _smty;
        devAddr = _devAddr;
        genesisSmtyPerBlock = _genesisSmtyPerBlock;
        startBlock = _startBlock;
        blocksInGenesisEpoch = _blocksInGenesisEpoch;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        address _rewardedToken,
        bool _withUpdate
    )
        public
        onlyOwner
    {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accSMTYPerShare: 0,
            rewardedToken: _rewardedToken
        }));
    }

    // Update the given pool's SMTY allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        address _rewardedToken,
        bool _withUpdate) public onlyOwner
    {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].rewardedToken = _rewardedToken;
    }

    // Return block rewards over the given _from (inclusive) to _to (inclusive) block.
    function getSmtyBlockReward(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_from > _to) {
            return 0;
        }

        uint256 blocksPerEpoch = blocksInGenesisEpoch;
        uint256 epochBegin = startBlock;
        uint256 epochEnd = epochBegin + blocksPerEpoch - 1;
        uint256 rewardPerBlock = genesisSmtyPerBlock;
        uint256 totalRewards = 0;
        uint256 multiplier = GENESIS_EPOCH_BONUS_MULTIPLIER;
        while (_to >= epochBegin) {
            uint256 left = Math.max(epochBegin, _from);
            uint256 right = Math.min(epochEnd, _to);
            if (right >= left) {
                totalRewards += (right - left + 1) * rewardPerBlock * multiplier;
            }

            multiplier = 1;
            rewardPerBlock = rewardPerBlock / 2;
            blocksPerEpoch = blocksPerEpoch * 2;
            epochBegin = epochEnd + 1;
            epochEnd = epochBegin + blocksPerEpoch - 1;
        }
        return totalRewards;
    }

    // View function to see pending SMTYs on frontend.
    function pendingSMTY(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSMTYPerShare = pool.accSMTYPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 smtyReward = getSmtyBlockReward(pool.lastRewardBlock + 1, block.number).mul(
                pool.allocPoint).div(totalAllocPoint);
            smtyReward = smtyReward.sub(smtyReward.div(10));
            accSMTYPerShare = accSMTYPerShare.add(smtyReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accSMTYPerShare).div(1e12).sub(user.smtyRewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public whenNotPaused {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 smtyReward = getSmtyBlockReward(pool.lastRewardBlock + 1, block.number).mul(
            pool.allocPoint).div(totalAllocPoint);
        smty.mint(devAddr, smtyReward.div(10));
        smtyReward = smtyReward.sub(smtyReward.div(10));
        smty.mint(address(this), smtyReward);
        pool.accSMTYPerShare = pool.accSMTYPerShare.add(smtyReward.mul(1e12).div(lpSupply));

        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to SmoothyMaster for SMTY allocation.
    function deposit(uint256 _pid, uint256 _amount) public whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 smtyPending = user.amount.mul(pool.accSMTYPerShare).div(1e12).sub(user.smtyRewardDebt);
            safeSMTYTransfer(msg.sender, smtyPending);
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.smtyRewardDebt = user.amount.mul(pool.accSMTYPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from SmoothyMaster.
    function _withdraw(
        uint256 _pid,
        uint256 _amount,
        address _depositor
    ) internal
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_depositor];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 smtyPending = user.amount
            .mul(pool.accSMTYPerShare)
            .div(1e12)
            .sub(user.smtyRewardDebt);
        safeSMTYTransfer(_depositor, smtyPending);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);

            pool.lpToken.safeTransfer(_depositor, _amount);
        }
        user.smtyRewardDebt = user.amount.mul(pool.accSMTYPerShare).div(1e12);
    }

    function withdraw(uint256 _pid, uint256 _amount) public whenNotPaused {
        _withdraw(_pid, _amount, msg.sender);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claim(uint256 _pid) public whenNotPaused {
        _withdraw(_pid, 0, msg.sender);
        emit Claim(msg.sender, _pid);
    }

    // In case we want to distribte reward offchain like BAL if we open a staking pool for BPT
    // Balaner is using a offline distribution method
    // https://github.com/balancer-labs/bal-mining-scripts
    function claimRewards(uint256 _pid) public {
        require(msg.sender == devAddr, "dev: wut?");

        PoolInfo storage pool = poolInfo[_pid];
        require(pool.rewardedToken != address(0), "reward token address not set");
        IERC20 rewardedToken = IERC20(pool.rewardedToken);
        uint256 balance = rewardedToken.balanceOf(address(this));
        if (balance > 0) {
            rewardedToken.safeTransfer(devAddr, balance);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(msg.sender, user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.smtyRewardDebt = 0;
    }

    // Safe smty transfer function, just in case if rounding error causes pool to not have enough SMTYs.
    function safeSMTYTransfer(address _to, uint256 _amount) internal {
        if (_amount > 0) {
            uint256 smtyBal = smty.balanceOf(address(this));
            if (_amount > smtyBal) {
                smty.transfer(_to, smtyBal);
            } else {
                smty.transfer(_to, _amount);
            }
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devAddr) public {
        require(msg.sender == devAddr, "dev: wut?");
        devAddr = _devAddr;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
