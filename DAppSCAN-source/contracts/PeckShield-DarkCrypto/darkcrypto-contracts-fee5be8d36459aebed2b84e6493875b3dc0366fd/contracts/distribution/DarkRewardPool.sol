// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract DarkRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;
    address public reserveFund;

    // flags
    uint256 private _locked = 0;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. DARKs to distribute per block.
        uint256 lastRewardTime; // Last timestamp that DARKs distribution occurs.
        uint256 accDarkPerShare; // Accumulated DARKs per share, times 1e18. See below.
        bool isStarted; // if lastRewardTime has passed
        uint16 depositFeeBP; // Deposit fee in basis points
        uint256 startTime;
    }

    address public dark;

    // DARK tokens created per second.
    uint256 public rewardPerSecond;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The timestamp when DARK mining starts.
    uint256 public startTime;
    uint256 public endTime;

    uint256 public nextHalvingTime;
    uint256 public rewardHalvingRate = 8000;
    bool public halvingChecked = true;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        address _dark,
        uint256 _rewardPerSecond,
        uint256 _startTime,
        address _reserveFund
    ) public {
        require(now < _startTime, "late");
        dark = _dark;
        rewardPerSecond = _rewardPerSecond;
        reserveFund = _reserveFund;
        startTime = _startTime;
        endTime = _startTime.add(3 weeks);
        nextHalvingTime = _startTime.add(7 days);
        operator = msg.sender;
    }

    modifier lock() {
        require(_locked == 0, "LOCKED");
        _locked = 1;
        _;
        _locked = 0;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "DarkRewardPool: caller is not the operator");
        _;
    }

    modifier checkHalving() {
        if (halvingChecked) {
            halvingChecked = false;
            if (now >= endTime) {
                massUpdatePools();
                rewardPerSecond = 0; // stop farming
                nextHalvingTime = type(uint256).max;
            } else {
                if (now >= nextHalvingTime) {
                    massUpdatePools();
                    rewardPerSecond = rewardPerSecond.mul(rewardHalvingRate).div(10000); // x80% (20% decreased every week)
                    nextHalvingTime = nextHalvingTime.add(7 days);
                }
                halvingChecked = true;
            }
        }
        _;
    }

    function resetStartTime(uint256 _startTime) external onlyOperator {
        require(startTime > now && _startTime > now, "late");
        startTime = _startTime;
        endTime = _startTime.add(10 weeks);
        nextHalvingTime = _startTime.add(7 days);
    }

    function setReserveFund(address _reserveFund) external onlyOperator {
        reserveFund = _reserveFund;
    }

    // anyone can stop this farming by rule
    function stopFarming() external {
        require(rewardPerSecond > 0, "already stopped");
        require(now >= endTime, "farming is not ended yet");
        massUpdatePools();
        rewardPerSecond = 0; // stop farming
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function checkPoolDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _lpToken, "add: existing pool?");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, uint256 _lastRewardTime) public onlyOperator {
        require(_allocPoint <= 100000, "too high allocation point"); // <= 100x
        require(_depositFeeBP <= 1000, "too high fee"); // <= 10%
        checkPoolDuplicate(_lpToken);
        massUpdatePools();
        if (now < startTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = startTime;
            } else {
                if (_lastRewardTime < startTime) {
                    _lastRewardTime = startTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < now) {
                _lastRewardTime = now;
            }
        }
        bool _isStarted = (_lastRewardTime <= startTime) || (_lastRewardTime <= now);
        poolInfo.push(
            PoolInfo({
            lpToken : _lpToken,
            allocPoint : _allocPoint,
            lastRewardTime : _lastRewardTime,
            accDarkPerShare : 0,
            isStarted : _isStarted,
            depositFeeBP : _depositFeeBP,
            startTime : _lastRewardTime
            })
        );
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's DARK allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP) public onlyOperator {
        require(_allocPoint <= 100000, "too high allocation point"); // <= 100x
        require(_depositFeeBP <= 1000, "too high fee"); // <= 10%
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
        pool.depositFeeBP = _depositFeeBP;
    }

    // View function to see pending DARKs on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDarkPerShare = pool.accDarkPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (now > pool.lastRewardTime && lpSupply != 0) {
            uint256 _time = now.sub(pool.lastRewardTime);
            if (totalAllocPoint > 0) {
                uint256 _darkReward = _time.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
                accDarkPerShare = accDarkPerShare.add(_darkReward.mul(1e18).div(lpSupply));
            }
        }
        return user.amount.mul(accDarkPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (now <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = now;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _time = now.sub(pool.lastRewardTime);
            uint256 _darkReward = _time.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            pool.accDarkPerShare = pool.accDarkPerShare.add(_darkReward.mul(1e18).div(lpSupply));
        }
        pool.lastRewardTime = now;
    }

    function _harvestReward(uint256 _pid, address _account) internal {
        UserInfo storage user = userInfo[_pid][_account];
        if (user.amount > 0) {
            PoolInfo storage pool = poolInfo[_pid];
            uint256 _claimableAmount = user.amount.mul(pool.accDarkPerShare).div(1e18).sub(user.rewardDebt);
            if (_claimableAmount > 0) {
                safeDarkTransfer(_account, _claimableAmount);
                emit RewardPaid(_account, _pid, _claimableAmount);
            }
        }
    }

    function deposit(uint256 _pid, uint256 _amount) public lock checkHalving {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        _harvestReward(_pid, msg.sender);
        if (_amount > 0) {
            // support deflation token
            IERC20 _lpToken = pool.lpToken;
            uint256 _before = _lpToken.balanceOf(address(this));
            _lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            uint256 _after = _lpToken.balanceOf(address(this));
            _amount = _after - _before;
            if (pool.depositFeeBP > 0) {
                uint256 _depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(reserveFund, _depositFee);
                user.amount = user.amount.add(_amount).sub(_depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accDarkPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public lock checkHalving {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        _harvestReward(_pid, msg.sender);
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDarkPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function withdrawAll(uint256 _pid) external {
        withdraw(_pid, userInfo[_pid][msg.sender].amount);
    }

    function harvestAllRewards() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            if (userInfo[pid][msg.sender].amount > 0) {
                withdraw(pid, 0);
            }
        }
    }

    // Safe dark transfer function, just in case if rounding error causes pool to not have enough DARKs.
    function safeDarkTransfer(address _to, uint256 _amount) internal {
        uint256 _darkBal = IERC20(dark).balanceOf(address(this));
        if (_darkBal > 0) {
            if (_amount > _darkBal) {
                IERC20(dark).safeTransfer(_to, _darkBal);
            } else {
                IERC20(dark).safeTransfer(_to, _amount);
            }
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external lock {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) external onlyOperator {
        if (now < endTime.add(365 days)) {
            // do not allow to drain lpToken if less than 1 year after farming ends
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.lpToken, "pool.lpToken");
            }
        }
        _token.safeTransfer(_to, _amount);
    }
}
