// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;


import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/math/Math.sol";
import "./SMTYToken.sol";
import "../UpgradeableOwnable.sol";


contract SmoothyMasterV1 is UpgradeableOwnable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 workingAmount; // actual amount * ve boost * lockup bonus
        uint256 smtyRewardDebt; // Reward debt.
        uint256 lockEnd;
        uint256 lockDuration;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool.
        uint256 lastRewardTime;   // Last block timestamp that SMTYs distribution occurs.
        uint256 accSMTYPerShare;  // Accumulated SMTYs per share, times 1e18. See below.
        uint256 workingSupply;    // Total supply of working amount

        mapping (address => UserInfo) userInfo;
    }

    // The SMTY TOKEN!
    SMTYToken public smty;
    IERC20 public veSMTY;

    address public teamAddr;
    address public communityAddr;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The time when SMTY mining starts.
    uint256 public startTime;

    uint256 public constant MAX_TIME = 730 days; // 2 years
    uint256 public constant MAX_EXTRA_BOOST = 3e18; // 1x to 4x
    uint256 public constant EMISSION_DURATION = 10 * 365 days; // about 10 years
    uint256 public constant REWARD_PER_SECOND = 94000000e18 / EMISSION_DURATION;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event WorkingAmountUpdate(
        address indexed user,
        uint256 indexed pid,
        uint256 newWorkingAmount,
        uint256 newWorkingSupply
    );
    event LockCreate(address indexed user, uint256 indexed pid, uint256 amount, uint256 lockEnd, uint256 lockDuration);
    event LockExtend(address indexed user, uint256 indexed pid, uint256 amount, uint256 lockEnd, uint256 lockDuration);
    event LockAdd(address indexed user, uint256 indexed pid, uint256 amount, uint256 lockEnd, uint256 lockDuration);
    event LockIncreaseAmount(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 lockEnd,
        uint256 lockDuration
    );

    // solium-disable-next-line
    constructor() public {
    }

    function initialize(
        SMTYToken _smty,
        IERC20 _veSMTY,
        address _teamAddr,
        address _communityAddr,
        uint256 _startTime
    )
        external
        onlyOwner
    {
        smty = _smty;
        veSMTY = _veSMTY;
        teamAddr = _teamAddr;
        communityAddr = _communityAddr;
        startTime = _startTime;
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
    )
        public
        onlyOwner
    {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accSMTYPerShare: 0,
            workingSupply: 0
        }));
    }

    // Update the given pool's SMTY allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    )
        public
        onlyOwner
    {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return block rewards over the given _from (inclusive) to _to (inclusive) block.
    function getSmtyBlockReward(uint256 _from, uint256 _to) public view returns (uint256) {
        uint256 to = _to;
        if (to > startTime + EMISSION_DURATION) {
            to = startTime + EMISSION_DURATION;
        }

        uint256 from = _from;
        if (from < startTime) {
            from = startTime;
        }

        if (from > to) {
            return 0;
        }

        return (to - from + 1).mul(REWARD_PER_SECOND);
    }

    // View function to see pending SMTYs on frontend.
    function pendingSMTY(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = pool.userInfo[_user];
        uint256 accSMTYPerShare = pool.accSMTYPerShare;
        uint256 workingSupply = pool.workingSupply;
        if (block.timestamp > pool.lastRewardTime && workingSupply != 0) {
            uint256 smtyReward = getSmtyBlockReward(pool.lastRewardTime + 1, block.timestamp).mul(
                pool.allocPoint).div(totalAllocPoint);
            uint256 teamReward = smtyReward.mul(20).div(94);
            uint256 communityReward = smtyReward.mul(10).div(94);
            smtyReward = smtyReward.sub(communityReward).sub(teamReward);
            accSMTYPerShare = accSMTYPerShare.add(smtyReward.mul(1e18).div(workingSupply));
        }
        return user.workingAmount.mul(accSMTYPerShare).div(1e18).sub(user.smtyRewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        // SWC-113-DoS with Failed Call: L182 - L184
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        _updatePool(_pid, block.timestamp);
    }

    function _updatePool(uint256 _pid, uint256 _timestamp) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (_timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 workingSupply = pool.workingSupply;
        if (workingSupply == 0) {
            pool.lastRewardTime = _timestamp;
            return;
        }
        uint256 smtyReward = getSmtyBlockReward(pool.lastRewardTime + 1, _timestamp).mul(
            pool.allocPoint).div(totalAllocPoint);
        uint256 teamReward = smtyReward.mul(20).div(94);
        uint256 communityReward = smtyReward.mul(10).div(94);
        smty.mint(teamAddr, teamReward);
        smty.mint(communityAddr, communityReward);
        smtyReward = smtyReward.sub(communityReward).sub(teamReward);
        smty.mint(address(this), smtyReward);
        pool.accSMTYPerShare = pool.accSMTYPerShare.add(smtyReward.mul(1e18).div(workingSupply));

        pool.lastRewardTime = _timestamp;
    }

    modifier claimSmty(uint256 _pid, address _account, uint256 _timestamp) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = pool.userInfo[_account];
        _updatePool(_pid, _timestamp);
        if (user.workingAmount > 0) {
            uint256 smtyPending = user.workingAmount.mul(pool.accSMTYPerShare).div(1e18).sub(user.smtyRewardDebt);
            safeSMTYTransfer(_account, smtyPending);
            emit Claim(_account, _pid, smtyPending);
        }

        _; // amount/boost may be changed

        _updateWorkingAmount(_pid, _account);
        user.smtyRewardDebt = user.workingAmount.mul(pool.accSMTYPerShare).div(1e18);
    }

    function _updateWorkingAmount(
        uint256 _pid,
        address _account
    ) internal
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = pool.userInfo[_account];

        uint256 lim = user.amount.mul(4) / 10;

        uint256 votingBalance = veSMTY.balanceOf(_account);
        uint256 totalBalance = veSMTY.totalSupply();

        if (totalBalance != 0) {
            uint256 lsupply = pool.lpToken.totalSupply();
            lim = lim.add(lsupply.mul(votingBalance).div(totalBalance).mul(6) / 10);
        }

        uint256 veAmount = Math.min(user.amount, lim);

        uint256 timelockBoost = user.lockDuration.mul(MAX_EXTRA_BOOST).div(MAX_TIME).add(1e18);
        uint256 newWorkingAmount = veAmount.mul(timelockBoost).div(1e18);

        pool.workingSupply = pool.workingSupply.sub(user.workingAmount).add(newWorkingAmount);
        user.workingAmount = newWorkingAmount;

        emit WorkingAmountUpdate(_account, _pid, user.workingAmount, pool.workingSupply);
    }

    /*
     * Deposit without lock.
     */
    function deposit(uint256 _pid, uint256 _amount) external claimSmty(_pid, msg.sender, block.timestamp) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = pool.userInfo[msg.sender];

        require(user.lockDuration == 0, "must be unlocked");

        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    function createLock(uint256 _pid, uint256 _amount, uint256 _end) external {
        _createLock(_pid, _amount, _end, block.timestamp);
    }

    function _createLock(
        uint256 _pid,
        uint256 _amount,
        uint256 _end,
        uint256 _timestamp
    )
        internal
        claimSmty(_pid, msg.sender, _timestamp)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = pool.userInfo[msg.sender];

        require(user.lockDuration == 0, "must be unlocked");
        require(_end > _timestamp, "end too short");
        require(_end <= _timestamp + MAX_TIME, "end too long");

        if (_amount != 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.lockEnd = _end;
        user.lockDuration = _end.sub(_timestamp);

        emit LockCreate(msg.sender, _pid, user.amount, user.lockEnd, user.lockDuration);
    }

    function extendLock(uint256 _pid, uint256 _end) external claimSmty(_pid, msg.sender, block.timestamp) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = pool.userInfo[msg.sender];

        require(user.lockDuration != 0, "must be locked");
        require(_end <= block.timestamp + MAX_TIME, "end too long");
        require(_end > user.lockEnd, "new end must be greater");
        require(user.amount != 0, "user amount must be non-zero");

        user.lockDuration = Math.min(user.lockDuration.add(_end.sub(user.lockEnd)), MAX_TIME);
        user.lockEnd = _end;

        emit LockExtend(msg.sender, _pid, user.amount, user.lockEnd, user.lockDuration);
    }

    function increaseAmount(uint256 _pid, uint256 _amount) external claimSmty(_pid, msg.sender, block.timestamp) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = pool.userInfo[msg.sender];

        require(user.lockDuration != 0, "must be locked");
        require(user.lockEnd > block.timestamp, "must be non-expired");
        require(_amount != 0, "_amount must be nonzero");

        // Update duration according to new amount
        uint256 newAmount = user.amount.add(_amount);
        uint256 m0 = user.lockDuration.mul(user.amount);
        uint256 m1 = user.lockEnd.sub(block.timestamp).mul(_amount);
        uint256 newDuration = m0.add(m1).div(newAmount);
        user.lockDuration = newDuration;
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = newAmount;

        emit LockIncreaseAmount(msg.sender, _pid, user.amount, user.lockEnd, user.lockDuration);
    }

    function withdraw(uint256 _pid) public claimSmty(_pid, msg.sender, block.timestamp) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = pool.userInfo[msg.sender];

        require(user.lockEnd < block.timestamp, "must be expired");

        uint256 amount = user.amount;
        user.amount = 0;
        user.lockDuration = 0; // mark it as unlocked

        pool.lpToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, _pid, amount);
    }

    // solium-disable-next-line
    function claim(uint256 _pid, address _account) public claimSmty(_pid, _account, block.timestamp) {
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

    function getUserInfo(uint256 _pid) public view returns(uint, uint, uint, uint, uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = pool.userInfo[msg.sender];

        return (user.amount, user.workingAmount, user.smtyRewardDebt, user.lockEnd, user.lockDuration);
    }
}
