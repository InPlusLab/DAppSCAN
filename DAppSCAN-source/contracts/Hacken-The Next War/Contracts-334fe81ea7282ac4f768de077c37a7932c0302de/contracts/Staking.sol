// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Staking is Ownable {
    using SafeMath for uint256;

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
    uint256 public tngPerSecond = 1 * 10**18;
    uint256 public lpTokenDeposited;
    uint256 public pendingTngRewards;

    uint256 private constant ACC_TNG_PRECISION = 1e12;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 sid, uint256 amount);
    event Harvest(address indexed user, uint256 amount);
    event LogTngPerSecond(uint256 tngPerSecond);

    constructor(IERC20 _tngToken, IERC20 _lpToken, uint256 _lockTime) {
        tngToken = _tngToken;
        lpToken = _lpToken;
        lockTime = _lockTime;
    }

    function deposit(uint256 amount) external {
        // Refresh rewards
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        UserStakeInfo storage stakeInfo = userStakeInfo[user.stakeRecords][msg.sender];
        require(tngToken.balanceOf(msg.sender) >= amount, "Insufficient tokens");

        // set user info
        user.totalAmount = user.totalAmount.add(amount);
        user.rewardDebt = user.rewardDebt.add(amount.mul(accTngPerShare) / ACC_TNG_PRECISION);
        user.stakeRecords = user.stakeRecords.add(1);

        // set staking info
        stakeInfo.amount = amount;
        stakeInfo.stakedTime = block.timestamp;
        stakeInfo.unlockTime = block.timestamp + lockTime;

        // Tracking
        lpTokenDeposited = lpTokenDeposited.add(amount);

        // Transfer token into the contract
// SWC-104-Unchecked Call Return Value: L80
        lpToken.transferFrom(msg.sender, address(this), amount);
        
        emit Deposit(msg.sender, amount);
    }

    function harvest() external {
        // Refresh rewards
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        uint256 accumulatedTng = user.totalAmount.mul(accTngPerShare) / ACC_TNG_PRECISION;
        uint256 _pendingTng = accumulatedTng.sub(user.rewardDebt);
        require(_pendingTng > 0, "No pending rewards");
        require(lpToken.balanceOf(address(this)) >= _pendingTng, "Insufficient tokens in contract");

        // user info
        user.rewardDebt = accumulatedTng;
        user.lastClaimTime = block.timestamp;

        // Transfer pending rewards if there is any
        payTngReward(_pendingTng, msg.sender);

        emit Harvest(msg.sender, _pendingTng);
    }

    /// @notice Withdraw LP tokens from MC and harvest proceeds for transaction sender to `to`.
    /// @param sid The index of the staking record
    function withdraw(uint256 sid) external {
        // Refresh rewards
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        UserStakeInfo storage stakeInfo = userStakeInfo[sid][msg.sender];

        uint256 _amount = stakeInfo.amount;
        require(_amount > 0, "No stakes found");
        require(block.timestamp >= stakeInfo.unlockTime, "Lock period not ended");
        require(lpToken.balanceOf(address(this)) >= _amount, "Insufficient tokens in contract, please contact admin");

        uint256 accumulatedTng = user.totalAmount.mul(accTngPerShare) / ACC_TNG_PRECISION;
        uint256 _pendingTng = accumulatedTng.sub(user.rewardDebt);

        // user info
        user.rewardDebt = accumulatedTng.sub(_amount.mul(accTngPerShare) / ACC_TNG_PRECISION);
        user.totalAmount = user.totalAmount.sub(_amount);

        // Stake info
        stakeInfo.amount = 0;
        stakeInfo.unstakedTime = block.timestamp;

        // Tracking
        lpTokenDeposited = lpTokenDeposited.sub(_amount);

        // Transfer tokens to user
// SWC-104-Unchecked Call Return Value: L135
        lpToken.transfer(msg.sender, _amount);

        // Transfer pending rewards if there is any
        if (_pendingTng != 0) {
            user.lastClaimTime = block.timestamp;
            payTngReward(_pendingTng, msg.sender);
        }

        emit Withdraw(msg.sender, sid, _amount);
    }

    function pendingTng(address _user) external view returns (uint256 pending) {
        UserInfo storage user = userInfo[_user];
        uint256 _accTngPerShare = accTngPerShare;

        if (block.timestamp > lastRewardTime && lpTokenDeposited != 0) {
            uint256 time = block.timestamp.sub(lastRewardTime);
            uint256 tngReward = getTngRewardForTime(time);
            
            _accTngPerShare = accTngPerShare.add(tngReward.mul(ACC_TNG_PRECISION) / lpTokenDeposited);
        }
        pending = (user.totalAmount.mul(_accTngPerShare) / ACC_TNG_PRECISION).sub(user.rewardDebt);
    }

    function updatePool() public {
 
        if (block.timestamp > lastRewardTime) {

            if (lpTokenDeposited > 0) {
                uint256 time = block.timestamp.sub(lastRewardTime);
                uint256 tngReward = getTngRewardForTime(time);

                trackPendingTngReward(tngReward);
                accTngPerShare = accTngPerShare.add(tngReward.mul(ACC_TNG_PRECISION) / lpTokenDeposited);
            }

            lastRewardTime = block.timestamp;
        }
    }

    function payTngReward(uint256 _pendingTng, address _to) internal {
        // SWC-104-Unchecked Call Return Value: L177
        tngToken.transfer(_to, _pendingTng);
        pendingTngRewards = pendingTngRewards.sub(_pendingTng);
    }

    function getTngRewardForTime(uint256 _time) public view returns (uint256) {
        uint256 tngReward = _time.mul(tngPerSecond);

        return tngReward;
    }

    function trackPendingTngReward(uint256 amount) internal {
        pendingTngRewards = pendingTngRewards.add(amount);
    }

    // Update TheNextWar Gem token address
    function setTngToken(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Zero address");
        tngToken = IERC20(newAddress);
    }

    function setLockTime(uint256 epoch) external onlyOwner {
        lockTime = epoch;
    }

    function setTngPerSecond(uint256 _tngPerSecond) external onlyOwner {
        tngPerSecond = _tngPerSecond;
        emit LogTngPerSecond(_tngPerSecond);
    }

    function rescueToken(address _token, address _to) external onlyOwner {
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        // SWC-104-Unchecked Call Return Value: L209
        IERC20(_token).transfer(_to, _contractBalance);
    }

	function clearStuckBalance() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    receive() external payable {}
}