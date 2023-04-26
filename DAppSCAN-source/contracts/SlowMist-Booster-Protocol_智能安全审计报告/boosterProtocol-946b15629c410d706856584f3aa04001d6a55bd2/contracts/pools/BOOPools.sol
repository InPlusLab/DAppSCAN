// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import '../interfaces/IActionTrigger.sol';
import '../interfaces/IActionPools.sol';
import "../BOOToken.sol";

// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Token is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract BOOPools is Ownable, IActionTrigger {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 rewardRemain;   // Remain rewards
        //
        // We do some fancy math here. Basically, any point in time, the amount of Token
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) + user.rewardRemain - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User calc the pending rewards and record at rewardRemain.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        address lpToken;             // Address of LP token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. Token to distribute per block.
        uint256 lastRewardBlock;    // Last block number that Token distribution occurs.
        uint256 accRewardPerShare;  // Accumulated Token per share, times 1e18. See below.
        uint256 totalAmount;        // Total amount of current pool deposit.
    }

    // The BOO TOKEN!
    BOOToken public rewardToken;
    // BOO tokens created per block.
    uint256 public rewardPerBlock;
    address public devaddr;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when reward Token mining starts.
    uint256 public startBlock;
    // The extend Pool
    address public extendPool;

    // block hacker user to deposit
    mapping (address => bool) public depositBlacklist;
    // block hacker user to restricted reward
    mapping (address => uint256) public rewardRestricted;
    // enable pool emergency withdraw
    mapping (uint256 => bool) public emergencyWithdrawEnabled;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor (
        address _rewardToken,
        uint256 _rewardPerBlock,
        address _devaddr,
        uint256 _startBlock
    ) public {
        rewardToken = BOOToken(_rewardToken);
        startBlock = _startBlock;
        devaddr = _devaddr;
        rewardPerBlock = _rewardPerBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getATPoolInfo(uint256 _pid) external override view 
        returns (address lpToken, uint256 allocRate, uint256 totalAmount) {
        lpToken = poolInfo[_pid].lpToken;
        totalAmount = poolInfo[_pid].totalAmount;
        if(totalAllocPoint > 0) {
            allocRate = poolInfo[_pid].allocPoint.mul(1e9).div(totalAllocPoint);
        }else{
            allocRate = 1e9;
        }
    }

    function getATUserAmount(uint256 _pid, address _account) external override view 
        returns (uint256 acctAmount) {
        acctAmount = userInfo[_pid][_account].amount;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, address _lpToken) public onlyOwner {
        massUpdatePools();
        require(IERC20(_lpToken).totalSupply() >= 0, 'error lptoken address');
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accRewardPerShare: 0,
            totalAmount: 0
        }));
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
    }

    // Set the number of reward produced by each block
    function setRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        massUpdatePools();
        rewardPerBlock = _rewardPerBlock;
    }

    function setExtendPool(address _extendPool) external onlyOwner {
        extendPool = _extendPool;
    }

    // Update the given pool's Token allocation point. Can only be called by the owner.
    function setAllocPoint(uint256 _pid, uint256 _allocPoint) external onlyOwner {
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update dev address by the previous one
    function setDevAddress(address _devaddr) external {
        require(msg.sender == devaddr, "only dev caller");
        devaddr = _devaddr;
    }

    // block hacker user to deposit
    function setBlacklist(address _hacker, bool _set) external onlyOwner {
        depositBlacklist[_hacker] = _set;
    }

    function setEmergencyWithdrawEnabled(uint256 _pid, bool _set) external onlyOwner {
        emergencyWithdrawEnabled[_pid] = _set;
    }

    // block hacker user to restricted reward
    function setRewardRestricted(address _hacker, uint256 _rate) external onlyOwner {
        require(_rate <= 1e9, 'max is 1e9');
        rewardRestricted[_hacker] = _rate;
    }

    // Return reward multiplier over the given _from to _to block.
    function getBlocksReward(uint256 _from, uint256 _to) public view returns (uint256 value) {
        require(_from <= _to, 'getBlocksReward error');
        if (_to < startBlock) {
            return 0;
        }
        if (_from < startBlock && _to >= startBlock) {
            value = getBlocksReward(startBlock, _to);
        } else {
            value = _to.sub(_from).mul(rewardPerBlock);
        }
    }

    // View function to see pending Tokens on frontend.
    function pendingRewards(uint256 _pid, address _user) public view returns (uint256 value) {
        value = totalRewards(_pid, _user)
                    .add(userInfo[_pid][_user].rewardRemain)
                    .sub(userInfo[_pid][_user].rewardDebt);
    }

    function totalRewards(uint256 _pid, address _user) public view returns (uint256 value) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        if (block.number > pool.lastRewardBlock && pool.totalAmount != 0) {
            uint256 poolReward = getBlocksReward(pool.lastRewardBlock, block.number)
                                    .mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(poolReward.mul(1e18).div(pool.totalAmount));
        }
        value = userInfo[_pid][_user].amount.mul(accRewardPerShare).div(1e18);
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
        if (pool.allocPoint == 0 || pool.totalAmount == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 poolReward = getBlocksReward(pool.lastRewardBlock, block.number)
                                .mul(pool.allocPoint).div(totalAllocPoint);
        if (poolReward > 0) {
            rewardToken.mint(address(this), poolReward);
            rewardToken.mint(devaddr, poolReward.div(8));
            pool.accRewardPerShare = pool.accRewardPerShare.add(poolReward.mul(1e18).div(pool.totalAmount));
        }
        pool.lastRewardBlock = block.number;

        if(extendPool != address(0)) {
            IActionPools(extendPool).onAcionUpdate(_pid);
        }
    }

    // Deposit LP tokens to MasterChef for Token allocation.
    function deposit(uint256 _pid, uint256 _amount) external {
        require(!depositBlacklist[msg.sender], 'user in blacklist');
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount > 0) {
            user.rewardRemain = pendingRewards(_pid, msg.sender);
        }
        uint256 amountOld = user.amount;
        if(_amount > 0) {
            IERC20(pool.lpToken).safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
        }
        user.rewardDebt = totalRewards(_pid, msg.sender);
        emit Deposit(msg.sender, _pid, _amount);

        if(extendPool != address(0)) {
            IActionPools(extendPool).onAcionIn(_pid, msg.sender, amountOld, user.amount);
        }
    }

    // Withdraw LP tokens from StarPool.
    function withdraw(uint256 _pid, uint256 _amount) external {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        user.rewardRemain = pendingRewards(_pid, msg.sender);
        uint256 amountOld = user.amount;
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            IERC20(pool.lpToken).safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = totalRewards(_pid, msg.sender);
        emit Withdraw(msg.sender, _pid, _amount);        
        
        if(extendPool != address(0)) {
            IActionPools(extendPool).onAcionOut(_pid, msg.sender, amountOld, user.amount);
        }
    }

    function claim(uint256 _pid) public returns (uint256 value) {
        updatePool(_pid);
        value = pendingRewards(_pid, msg.sender);
        if (value > 0) {
            userInfo[_pid][msg.sender].rewardRemain = 0;
            if(rewardRestricted[msg.sender] > 0) {
                value = value.sub(value.mul(rewardRestricted[msg.sender]).div(1e9));
            }
            value = safeTokenTransfer(msg.sender, value);
            userInfo[_pid][msg.sender].rewardDebt = totalRewards(_pid, msg.sender);
        }

        emit Claim(msg.sender, _pid, value);        

        if(extendPool != address(0)) {
            IActionPools(extendPool).onAcionClaim(_pid, msg.sender);
        }
    }

    function claimAll() external returns (uint256 value) {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            claim(pid);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        require(emergencyWithdrawEnabled[_pid], 'not allowed');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardRemain = 0;
        pool.totalAmount = pool.totalAmount.sub(amount);
        IERC20(pool.lpToken).safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);        
        
        if(extendPool != address(0)) {
            IActionPools(extendPool).onAcionEmergency(_pid, msg.sender);
        }
    }

    // Safe Token transfer function, just in case if rounding error causes pool to not have enough Tokens.
    function safeTokenTransfer(address _to, uint256 _amount) internal returns (uint256 value) {
        uint256 balance = rewardToken.balanceOf(address(this));
        value = _amount > balance ? balance : _amount;
        if ( value > 0 ) {
            rewardToken.transfer(_to, value);
        }
    }

    // If the user transfers TH to contract, it will revert
    receive() external payable {
        revert();
    }
}
