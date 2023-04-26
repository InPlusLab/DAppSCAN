// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../protocol/WNativeRelayer.sol";

contract FeeDistribute is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  address public wNative;
  address public wNativeRelayer;

  struct UserInfo {
    uint256 amount; // User deposited amount.
    uint256 rewardDebt;
  }

  // Info of each pool.
  struct PoolInfo {
    address stakeToken; // Address of Staking Token contract.
    address rewardToken; // Address of Reward Token contract.
    uint256 depositedAmount; // Total depoosited amount.
    uint256 latestRewardAmount;
    uint256 totalRewardAmount;
    uint256 rewardPerShare; // Rewards per share,
  }

  uint256 private constant PRECISION = 1e12;

  // Info of each pool.
  PoolInfo[] public poolInfo;
  // Info of each user that stakes Staking tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  // Check pool exist by Reward Token.
  mapping(address => bool) public isPoolExist;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

  constructor(address _wNative, address _wNativeRelayer) public {
    wNative = _wNative;
    wNativeRelayer = _wNativeRelayer;
  }

  function setParams(address _wNative, address _wNativeRelayer) public onlyOwner {
    wNative = _wNative;
    wNativeRelayer = _wNativeRelayer;
  }

  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }

  // Add a new Token to the pool. Can only be called by the owner.
  function addPool(address _stakeToken, address _rewardToken) external onlyOwner {
    massUpdatePools();
    require(_stakeToken != address(0), "FeeDistribute::addPool:: not ZERO address.");
    require(!isPoolExist[_rewardToken], "FeeDistribute::addPool:: pool exist.");
    poolInfo.push(
      PoolInfo({
        stakeToken: _stakeToken,
        rewardToken: _rewardToken,
        depositedAmount: 0,
        latestRewardAmount: 0,
        totalRewardAmount: 0,
        rewardPerShare: 0
      })
    );
    isPoolExist[_rewardToken] = true;
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
    uint256 _rewardBalance = IERC20(pool.rewardToken).balanceOf(address(this));
    uint256 _pendingReward = _rewardBalance.sub(pool.latestRewardAmount);
    uint256 _totalDeposited = pool.depositedAmount;

    if (_pendingReward != 0 && _totalDeposited != 0) {
      uint256 _pendingRewardPerShare = _pendingReward.mul(PRECISION).div(_totalDeposited);
      pool.totalRewardAmount = pool.totalRewardAmount.add(_pendingReward);
      pool.latestRewardAmount = _rewardBalance;
      pool.rewardPerShare = pool.rewardPerShare.add(_pendingRewardPerShare);
    }
  }

  function poolPendingReward(uint256 _pid) public view returns (uint256) {
    PoolInfo storage pool = poolInfo[_pid];
    uint256 _rewardBalance = IERC20(pool.rewardToken).balanceOf(address(this));
    return _rewardBalance.sub(pool.latestRewardAmount);
  }

  function poolTotalReward(uint256 _pid) public view returns (uint256) {
    PoolInfo storage pool = poolInfo[_pid];
    return pool.totalRewardAmount.add(poolPendingReward(_pid));
  }

  // View function to see pending Reward on frontend.
  function pendingReward(address _user, uint256 _pid) public view returns (uint256) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 _rewardPerShare = pool.rewardPerShare;
    uint256 _rewardBalance = IERC20(pool.rewardToken).balanceOf(address(this));
    uint256 _pendingReward = _rewardBalance.sub(pool.latestRewardAmount);
    uint256 _totalDeposited = pool.depositedAmount;

    if (_pendingReward != 0 && _totalDeposited != 0) {
      uint256 _pendingRewardPerShare = _pendingReward.mul(PRECISION).div(_totalDeposited);
      _rewardPerShare = _rewardPerShare.add(_pendingRewardPerShare);
    }
    return user.amount.mul(_rewardPerShare).div(PRECISION).sub(user.rewardDebt);
  }

  // Deposit Staking tokens to earn reward.
  function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(pool.stakeToken != address(0), "FeeDistribute::deposit:: not accept deposit.");
    updatePool(_pid);
    if (user.amount > 0) _harvest(_pid);
    if (_amount > 0) {
      IERC20(pool.stakeToken).safeTransferFrom(address(msg.sender), address(this), _amount);
      user.amount = user.amount.add(_amount);
      pool.depositedAmount = pool.depositedAmount.add(_amount);
    }
    user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(PRECISION);
    emit Deposit(msg.sender, _pid, _amount);
  }

  // Withdraw Staking tokens.
  function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
    _withdraw(_pid, _amount);
  }

  function withdrawAll(uint256 _pid) external nonReentrant {
    _withdraw(_pid, userInfo[_pid][msg.sender].amount);
  }

  function _withdraw(uint256 _pid, uint256 _amount) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount >= _amount, "FeeDistribute::withdraw:: not good.");
    updatePool(_pid);
    if (user.amount > 0) _harvest(_pid);
    if (_amount > 0) {
      user.amount = user.amount.sub(_amount);
      user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(PRECISION);
      pool.depositedAmount = pool.depositedAmount.sub(_amount);
      if (pool.stakeToken != address(0)) {
        IERC20(pool.stakeToken).safeTransfer(address(msg.sender), _amount);
      }
    }
    emit Withdraw(msg.sender, _pid, _amount);
  }

  // Harvest RewardToken earn from the pool.
  function harvest(uint256 _pid) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    updatePool(_pid);
    _harvest(_pid);
    user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(PRECISION);
  }

  function _harvest(uint256 _pid) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount > 0, "FeeDistribute::harvest:: nothing to harvest.");
    uint256 pending = user.amount.mul(pool.rewardPerShare).div(PRECISION).sub(user.rewardDebt);
    if (pending > 0) {
      pool.latestRewardAmount = pool.latestRewardAmount.sub(pending);
      if (pool.rewardToken == wNative) {
        IERC20(pool.rewardToken).safeTransfer(wNativeRelayer, pending);
        WNativeRelayer(payable(wNativeRelayer)).withdraw(pending);
        (bool success, ) = msg.sender.call{ value: pending }(new bytes(0));
        require(success, "!safeTransfer");
      } else {
        IERC20(pool.rewardToken).safeTransfer(msg.sender, pending);
      }
    }
    emit Harvest(msg.sender, _pid, pending);
  }

  // Withdraw without caring about rewards. EMERGENCY ONLY.
  function emergencyWithdraw(uint256 _pid) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    uint256 amount = user.amount;
    if (amount > 0) {
      uint256 pending = amount.mul(pool.rewardPerShare).div(PRECISION).sub(user.rewardDebt);
      if (pending > 0) {
        pool.latestRewardAmount = pool.latestRewardAmount.sub(pending);
      }
      pool.depositedAmount = pool.depositedAmount.sub(amount);
      user.amount = 0;
      user.rewardDebt = 0;
      IERC20(pool.stakeToken).safeTransfer(address(msg.sender), amount);
    }
    emit EmergencyWithdraw(msg.sender, _pid, amount);
  }

  receive() external payable {}
}
