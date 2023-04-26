// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Staking is Ownable {

    /// @notice Info of each MC user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of TNG entitled to the user.
    struct UserInfo {
        uint256 totalAmount;
        uint256 rewardDebt;
        uint256 lastClaimTime;
        uint256 stakeRecords;
    }

    // Store all user stake records
    struct UserStakeInfo {
        uint256 amount;
        uint256 stakedTime;
        uint256 unstakedTime;
        uint256 unlockTime;
    }

    // Info of each user that stakes.
    mapping (address => UserInfo) public userInfo;
    // Info of each user staking records
    mapping (uint256 => mapping (address => UserStakeInfo)) public userStakeInfo;

    IERC20 public tngToken;
    IERC20 public lpToken;
    uint256 public accTngPerShare;
    uint256 public lastRewardTime = block.timestamp;
    uint256 public lockTime;    // lock time in seconds
    uint256 public tngPerSecond = 578700000000000000;   //Initial rewards per seconds = 50000/86400
    uint256 public lpTokenDeposited;
    uint256 public pendingTngRewards;
    uint256 public emergencyWithdrawalFee = 10; // Early withdrawal will incur 10% fee, fee will be stored in contract

    uint256 private constant ACC_TNG_PRECISION = 1e12;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 sid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 sid, uint256 amount);
    event Harvest(address indexed user, uint256 amount);
    event SetTngPerSecond(uint256 tngPerSecond);
    event SetLockTime(uint256 epoch);
    event SetEmergencyWithdrawalFee(uint256 _emergencyWithdrawalFee);

    constructor(IERC20 _tngToken, IERC20 _lpToken, uint256 _lockTime) {
        tngToken = _tngToken;
        lpToken = _lpToken;
        lockTime = _lockTime;
    }

    function deposit(uint256 _amount) external {
        // Refresh rewards
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        UserStakeInfo storage stakeInfo = userStakeInfo[user.stakeRecords][msg.sender];
        require(lpToken.balanceOf(msg.sender) >= _amount, "Insufficient tokens");

        // set user info
        user.totalAmount += _amount;
        user.rewardDebt = user.rewardDebt + (_amount * accTngPerShare / ACC_TNG_PRECISION);
        user.stakeRecords++;

        // set staking info
        stakeInfo.amount = _amount;
        stakeInfo.stakedTime = block.timestamp;
        stakeInfo.unlockTime = block.timestamp + lockTime;

        // Tracking
        lpTokenDeposited = lpTokenDeposited + _amount;

        // Transfer token into the contract
        bool status = lpToken.transferFrom(msg.sender, address(this), _amount);
        require(status, "Deposit failed");

        emit Deposit(msg.sender, _amount);
    }

    function harvest() external {
        // Refresh rewards
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        uint256 accumulatedTng = user.totalAmount * accTngPerShare / ACC_TNG_PRECISION;
        uint256 _pendingTng = accumulatedTng - user.rewardDebt;
        require(_pendingTng > 0, "No pending rewards");
        require(tngToken.balanceOf(address(this)) >= _pendingTng, "Insufficient TNG tokens in contract");

        // user info
        user.rewardDebt = accumulatedTng;
        user.lastClaimTime = block.timestamp;

        // Transfer pending rewards if there is any
        payTngReward(_pendingTng, msg.sender);

        emit Harvest(msg.sender, _pendingTng);
    }

    /// @notice Withdraw LP tokens from MC and harvest proceeds for transaction sender to `to`.
    /// @param _sid The index of the staking record
    function withdraw(uint256 _sid) external {
        // Refresh rewards
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        UserStakeInfo storage stakeInfo = userStakeInfo[_sid][msg.sender];

        uint256 _amount = stakeInfo.amount;
        require(_amount > 0, "No stakes found");
        require(block.timestamp >= stakeInfo.unlockTime, "Lock period not ended");
        require(lpToken.balanceOf(address(this)) >= _amount, "Insufficient tokens in contract, please contact admin");

        uint256 accumulatedTng = user.totalAmount * accTngPerShare / ACC_TNG_PRECISION;
        uint256 _pendingTng = accumulatedTng - user.rewardDebt;

        // user info
        user.rewardDebt = accumulatedTng - (_amount * accTngPerShare / ACC_TNG_PRECISION);
        user.totalAmount -= _amount;

        // Stake info
        stakeInfo.amount = 0;
        stakeInfo.unstakedTime = block.timestamp;

        // Tracking
        lpTokenDeposited -= _amount;

        // Transfer tokens to user
        bool status = lpToken.transfer(msg.sender, _amount);
        require(status, "Failed to withdraw");

        // Transfer pending rewards if there is any
        if (_pendingTng != 0) {
            user.lastClaimTime = block.timestamp;
            payTngReward(_pendingTng, msg.sender);
        }

        emit Withdraw(msg.sender, _sid, _amount);
    }

    function emergencyWithdraw(uint256 _sid) external {
        UserInfo storage user = userInfo[msg.sender];
        UserStakeInfo storage stakeInfo = userStakeInfo[_sid][msg.sender];

        uint256 _amount = stakeInfo.amount;
        require(_amount > 0, "No stakes found");

        // user info
        user.totalAmount -= _amount;

        // Stake info
        stakeInfo.amount = 0;
        stakeInfo.unstakedTime = block.timestamp;

        // Tracking
        lpTokenDeposited -= _amount;

        // Early emergency withdrawal will incur penalty
        if(block.timestamp < stakeInfo.unlockTime) {
            _amount = _amount * (100 - emergencyWithdrawalFee) / 100;
        }

        // Transfer tokens to user
        bool status = lpToken.transfer(msg.sender, _amount);
        require(status, "Failed to withdraw");

        emit EmergencyWithdraw(msg.sender, _sid, _amount);
    }

    function pendingTng(address _user) external view returns (uint256 pending) {
        UserInfo storage user = userInfo[_user];
        uint256 _accTngPerShare = accTngPerShare;

        if (block.timestamp > lastRewardTime && lpTokenDeposited != 0) {
            uint256 time = block.timestamp - lastRewardTime;
            uint256 tngReward = getTngRewardForTime(time);
            
            _accTngPerShare = accTngPerShare + (tngReward * ACC_TNG_PRECISION / lpTokenDeposited);
        }
        pending = (user.totalAmount * _accTngPerShare / ACC_TNG_PRECISION) - user.rewardDebt;
    }

    function updatePool() public {
 
        if (block.timestamp > lastRewardTime) {

            if (lpTokenDeposited > 0) {
                uint256 time = block.timestamp - lastRewardTime;
                uint256 tngReward = getTngRewardForTime(time);

                trackPendingTngReward(tngReward);
                accTngPerShare = accTngPerShare + (tngReward * ACC_TNG_PRECISION / lpTokenDeposited);
            }

            lastRewardTime = block.timestamp;
        }
    }

    function payTngReward(uint256 _pendingTng, address _to) internal {
        pendingTngRewards = pendingTngRewards - _pendingTng;

        bool status = tngToken.transfer(_to, _pendingTng);
        require(status, "Failed to harvest");
    }

    function getTngRewardForTime(uint256 _time) public view returns (uint256) {
        uint256 tngReward = _time * tngPerSecond;

        return tngReward;
    }

    function trackPendingTngReward(uint256 _amount) internal {
        pendingTngRewards = pendingTngRewards + _amount;
    }

    function setLockTime(uint256 _epoch) external onlyOwner {
        lockTime = _epoch;

        emit SetLockTime(_epoch);
    }

    function setTngPerSecond(uint256 _tngPerSecond) external onlyOwner {
        tngPerSecond = _tngPerSecond;

        emit SetTngPerSecond(_tngPerSecond);
    }
    
    function setEmergencyWithdrawalFee(uint256 _emergencyWithdrawalFee) external onlyOwner {
        require(_emergencyWithdrawalFee <= 20, "Exceeded allowed threshold");
        emergencyWithdrawalFee = _emergencyWithdrawalFee;

        emit SetEmergencyWithdrawalFee(_emergencyWithdrawalFee);
    }
}