// SPDX-License-Identifier: MIT
// SWC-102-Outdated Compiler Version: L3
pragma solidity 0.6.6;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./MeowToken.sol";
import "./DevelopmentFund.sol";

// MeowMining is a smart contract for distributing MEOW by asking user to stake the ERC20-based token.
contract MeowMining is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // Info of each user.
  struct UserInfo {
    uint256 amount; // How many Staking tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below.
    address fundedBy; // Funded by who?
    uint256 lockedAmount; // How many Reward tokens locked.
    uint256 lastUnlockTime; // last time that Reward tokens unlocked.
    uint256 lockTo; // Time that Reward tokens locked to.
    //
    // We do some fancy math here. Basically, any point in time, the amount of MEOWs
    // entitled to a user but is pending to be distributed is:
    //
    //   pending reward = (user.amount * pool.accMeowPerShare) - user.rewardDebt
    //
    // Whenever a user deposits or withdraws Staking tokens to a pool. Here's what happens:
    //   1. The pool's `accMeowPerShare` (and `lastRewardTime`) gets updated.
    //   2. User receives the pending reward sent to his/her address.
    //   3. User's `amount` gets updated.
    //   4. User's `rewardDebt` gets updated.
  }

  // Info of each pool.
  struct PoolInfo {
    address stakeToken; // Address of Staking token contract.
    uint256 allocPoint; // How many allocation points assigned to this pool. MEOWs to distribute per block.
    uint256 lastRewardTime; // Last block timestamp that MEOWs distribution occurs.
    uint256 accMeowPerShare; // Accumulated MEOWs per share, times 1e12. See below.
  }

  uint256 private constant ACC_MEOW_PRECISION = 1e12;

  // Meow Token.
  MeowToken public meow;
  // Dev address.
  address public devaddr;
  // MEOW tokens created per second.
  uint256 public meowPerSecond;

  // Info of each pool.
  PoolInfo[] public poolInfo;
  // Info of each user that stakes Staking tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  // Check pool exist by Stake Token.
  mapping(address => bool) public isPoolExist;
  // Total allocation poitns. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint;
  // The block number when MEOW mining starts.
  uint256 public startTime;
  // Time to lock Meow and release linearly.
  uint256 public lockPeriod = 90 days; // 3 months
  // Total Meow locked amount.
  uint256 public totalLock;
  // Portion of tokens that user can harvest instantly.
  uint256 public preShare;
  // Portion of tokens that have to lock and release linearly.
  uint256 public lockShare;
  // Development Fund address;
  DevelopmentFund public developmentFund;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event Lock(address indexed user, uint256 indexed pid, uint256 amount);
  event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
  event Unlock(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

  constructor(
    MeowToken _meow,
    uint256 _meowPerSecond,
    uint256 _startTime,
    uint256 _preShare,
    uint256 _lockShare,
    address _devaddr,
    DevelopmentFund _developmentFund
  ) public {
    totalAllocPoint = 0;
    meow = _meow;
    meowPerSecond = _meowPerSecond;
    startTime = block.timestamp > _startTime ? block.timestamp : _startTime;
    preShare = _preShare;
    lockShare = _lockShare;
    devaddr = _devaddr;
    developmentFund = _developmentFund;
    meow.approve(address(_developmentFund), uint256(-1));
  }

  // Update dev address by the previous dev.
  function setDev(address _devaddr) public {
    require(msg.sender == devaddr, "MeowMining::setDev:: Forbidden.");
    devaddr = _devaddr;
  }

  function setMeowPerSecond(uint256 _meowPerSecond) external onlyOwner {
    massUpdatePools();
    meowPerSecond = _meowPerSecond;
  }

  // Add a new Token to the pool. Can only be called by the owner.
  function addPool(uint256 _allocPoint, address _stakeToken) external onlyOwner {
    massUpdatePools();
    require(_stakeToken != address(0), "MeowMining::addPool:: not ZERO address.");
    require(!isPoolExist[_stakeToken], "MeowMining::addPool:: stakeToken duplicate.");
    uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
    totalAllocPoint = totalAllocPoint.add(_allocPoint);
    poolInfo.push(
      PoolInfo({ stakeToken: _stakeToken, allocPoint: _allocPoint, lastRewardTime: lastRewardTime, accMeowPerShare: 0 })
    );
    isPoolExist[_stakeToken] = true;
  }

  // Update the given pool's MEOW allocation point. Can only be called by the owner.
  function setPool(uint256 _pid, uint256 _allocPoint) external onlyOwner {
    massUpdatePools();
    totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
    poolInfo[_pid].allocPoint = _allocPoint;
  }

  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }

  function canManualMint() public view returns (uint256) {
    return meow.canManualMint();
  }

  function manualMint(address _to, uint256 _amount) external onlyOwner {
    require(_amount <= (canManualMint()), "MeowMining::manualMint:: manual mint limit exceeded.");
    meow.manualMint(_to, _amount);
  }

  // View function to see pending MEOWs on frontend.
  function pendingMeow(uint256 _pid, address _user) external view returns (uint256) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 accMeowPerShare = pool.accMeowPerShare;
    uint256 stakeTokenSupply = IERC20(pool.stakeToken).balanceOf(address(this));
    if (block.timestamp > pool.lastRewardTime && stakeTokenSupply > 0 && totalAllocPoint > 0) {
      uint256 time = block.timestamp.sub(pool.lastRewardTime);
      uint256 meowReward = time.mul(meowPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
      accMeowPerShare = accMeowPerShare.add(meowReward.mul(ACC_MEOW_PRECISION).div(stakeTokenSupply));
    }
    return user.amount.mul(accMeowPerShare).div(ACC_MEOW_PRECISION).sub(user.rewardDebt);
  }

  // Update reward for all pools.
  function massUpdatePools() public {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      updatePool(pid);
    }
  }

  // Update reward of the given pool.
  function updatePool(uint256 _pid) public {
    PoolInfo storage pool = poolInfo[_pid];
    if (block.timestamp > pool.lastRewardTime) {
      uint256 stakeTokenSupply = IERC20(pool.stakeToken).balanceOf(address(this));
      if (stakeTokenSupply > 0 && totalAllocPoint > 0) {
        uint256 time = block.timestamp.sub(pool.lastRewardTime);
        uint256 meowReward = time.mul(meowPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        // Every 11.4286 Meow minted will mint 1 Meow for dev, come from 80/7 = 11.4286 use 10,000 to avoid floating.
        uint256 devfund = meowReward.mul(10000).div(114286);
        meow.mint(address(this), devfund);
        meow.mint(address(this), meowReward);
        safeMeowTransfer(devaddr, devfund.mul(preShare).div(10000));
        developmentFund.lock(devfund.mul(lockShare).div(10000));
        pool.accMeowPerShare = pool.accMeowPerShare.add(meowReward.mul(ACC_MEOW_PRECISION).div(stakeTokenSupply));
      }
      pool.lastRewardTime = block.timestamp;
    }
  }

  // Deposit Staking tokens to MeowMining for MEOW allocation.
  function deposit(
    address _for,
    uint256 _pid,
    uint256 _amount
  ) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_for];
    if (user.fundedBy != address(0)) require(user.fundedBy == msg.sender, "MeowMining::deposit:: bad sof.");
    require(pool.stakeToken != address(0), "MeowMining::deposit:: not accept deposit.");
    updatePool(_pid);
    if (user.amount > 0) _harvest(_for, _pid);
    if (user.fundedBy == address(0)) user.fundedBy = msg.sender;
    IERC20(pool.stakeToken).safeTransferFrom(address(msg.sender), address(this), _amount);
    user.amount = user.amount.add(_amount);
    user.rewardDebt = user.amount.mul(pool.accMeowPerShare).div(ACC_MEOW_PRECISION);
    emit Deposit(msg.sender, _pid, _amount);
  }

  // Withdraw Staking tokens from MeowMining.
  function withdraw(
    address _for,
    uint256 _pid,
    uint256 _amount
  ) external nonReentrant {
    _withdraw(_for, _pid, _amount);
  }

  function withdrawAll(address _for, uint256 _pid) external nonReentrant {
    _withdraw(_for, _pid, userInfo[_pid][_for].amount);
  }

  function _withdraw(
    address _for,
    uint256 _pid,
    uint256 _amount
  ) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_for];
    require(user.fundedBy == msg.sender, "MeowMining::withdraw:: only funder.");
    require(user.amount >= _amount, "MeowMining::withdraw:: not good.");
    updatePool(_pid);
    _harvest(_for, _pid);
    user.amount = user.amount.sub(_amount);
    user.rewardDebt = user.amount.mul(pool.accMeowPerShare).div(ACC_MEOW_PRECISION);
    if (user.amount == 0) user.fundedBy = address(0);
    if (pool.stakeToken != address(0)) {
      IERC20(pool.stakeToken).safeTransfer(address(msg.sender), _amount);
    }
    emit Withdraw(msg.sender, _pid, user.amount);
  }

  // Harvest MEOWs earn from the pool.
  function harvest(uint256 _pid) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    updatePool(_pid);
    _harvest(msg.sender, _pid);
    user.rewardDebt = user.amount.mul(pool.accMeowPerShare).div(ACC_MEOW_PRECISION);
  }

  function _harvest(address _to, uint256 _pid) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_to];
    require(user.amount > 0, "MeowMining::harvest:: nothing to harvest.");
    uint256 pending = user.amount.mul(pool.accMeowPerShare).div(ACC_MEOW_PRECISION).sub(user.rewardDebt);
    uint256 preAmount = pending.mul(preShare).div(10000);
    uint256 lockAmount = pending.mul(lockShare).div(10000);
    lock(_pid, _to, lockAmount);
    require(preAmount <= meow.balanceOf(address(this)), "MeowMining::harvest:: not enough Meow.");
    safeMeowTransfer(_to, preAmount);
    emit Harvest(msg.sender, _pid, preAmount);
  }

  // Lock Meow reward for a period of time.
  function lock(
    uint256 _pid,
    address _holder,
    uint256 _amount
  ) internal {
    unlock(_pid, _holder);
    if (_amount > 0) {
      UserInfo storage user = userInfo[_pid][_holder];
      user.lockedAmount = user.lockedAmount.add(_amount);
      user.lockTo = block.timestamp.add(lockPeriod);
      totalLock = totalLock.add(_amount);
      emit Lock(_holder, _pid, _amount);
    }
  }

  // Return pending unlock reward.
  function availableUnlock(uint256 _pid, address _holder) public view returns (uint256) {
    UserInfo storage user = userInfo[_pid][_holder];
    if (block.timestamp >= user.lockTo) {
      return user.lockedAmount;
    } else {
      uint256 releaseTime = block.timestamp.sub(user.lastUnlockTime);
      uint256 lockTime = user.lockTo.sub(user.lastUnlockTime);
      return user.lockedAmount.mul(releaseTime).div(lockTime);
    }
  }

  // Unlock the locked reward.
  function unlock(uint256 _pid) public {
    unlock(_pid, msg.sender);
  }

  function unlock(uint256 _pid, address _holder) internal {
    UserInfo storage user = userInfo[_pid][_holder];
    user.lastUnlockTime = block.timestamp;
    uint256 amount = availableUnlock(_pid, _holder);
    if (amount > 0) {
      if (amount > meow.balanceOf(address(this))) {
        amount = meow.balanceOf(address(this));
      }
      user.lockedAmount = user.lockedAmount.sub(amount);
      totalLock = totalLock.sub(amount);
      safeMeowTransfer(_holder, amount);
      emit Unlock(_holder, _pid, amount);
    }
  }

  // Withdraw without caring about rewards. EMERGENCY ONLY.
  function emergencyWithdraw(uint256 _pid) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.fundedBy == msg.sender, "MeowMining::emergencyWithdraw:: only funder.");
    IERC20(pool.stakeToken).safeTransfer(address(msg.sender), user.amount);
    emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    user.amount = 0;
    user.rewardDebt = 0;
    user.fundedBy = address(0);
  }

  // Safe meow transfer function, just in case if rounding error causes pool to not have enough MEOWs.
  function safeMeowTransfer(address _to, uint256 _amount) internal {
    uint256 meowBal = meow.balanceOf(address(this));
    if (_amount > meowBal) {
      require(meow.transfer(_to, meowBal), "MeowMining::safeMeowTransfer:: failed to transfer MEOW.");
    } else {
      require(meow.transfer(_to, _amount), "MeowMining::safeMeowTransfer:: failed to transfer MEOW.");
    }
  }
}
