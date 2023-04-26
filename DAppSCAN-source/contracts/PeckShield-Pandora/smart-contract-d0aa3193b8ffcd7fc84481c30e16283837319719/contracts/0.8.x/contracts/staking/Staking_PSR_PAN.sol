// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IMinter.sol";

contract StakingV1 is Ownable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    IERC20 public PAN;
    IERC20 public PSR;
    IMinter public minter;

    // governance
    address public reserveFund;

    uint256 public accRewardPerShare;
    uint256 public lastRewardBlock;
    uint256 public startRewardBlock;

    uint256 public rewardPerBlock;
    uint256 private constant ACC_REWARD_PRECISION = 1e12;

    mapping (address => UserInfo) public userInfo;

    /* ========== Modifiers =============== */


    constructor(IERC20 _PSR, IERC20 _PAN, IMinter _minter, uint256 _startReward, uint256 _rewardPerBlock) {
        PAN = _PAN;
        PSR = _PSR;
        lastRewardBlock = _startReward;
        startRewardBlock = _startReward;
        rewardPerBlock = _rewardPerBlock;
        minter = IMinter(_minter);
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /// @notice View function to see pending reward on frontend.
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingReward(address _user) external view returns (uint256 pending) {
        UserInfo storage user = userInfo[_user];
        uint256 supply = PSR.balanceOf(address(this));
        uint256 _accRewardPerShare = accRewardPerShare;
        if (block.number > lastRewardBlock && supply != 0) {
            uint256 rewardAmount = (block.number - lastRewardBlock) * rewardPerBlock;
            _accRewardPerShare += (rewardAmount * ACC_REWARD_PRECISION) / supply;
        }
        pending = uint256(int256(user.amount * _accRewardPerShare / ACC_REWARD_PRECISION) - user.rewardDebt);
    }

    /// @notice Update reward variables of the given pool.
    function updatePool() public {
        if (block.number > lastRewardBlock) {
            uint256 supply = PSR.balanceOf(address(this));
            if (supply > 0 && block.number > lastRewardBlock) {
                uint256 rewardAmount = (block.number - lastRewardBlock) * rewardPerBlock;
                accRewardPerShare += rewardAmount * ACC_REWARD_PRECISION / supply;
            }
            lastRewardBlock = block.number;
            emit LogUpdatePool(lastRewardBlock, supply, accRewardPerShare);
        }
    }

    /// @notice Deposit LP tokens to MCV2 for reward allocation.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(uint256 amount, address to) public {
        updatePool();
        UserInfo storage user = userInfo[to];

        // Effects
        user.amount += amount;
        user.rewardDebt += int256(amount * accRewardPerShare / ACC_REWARD_PRECISION);

        PSR.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount, to);
    }

    /// @notice Withdraw LP tokens from MCV2.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(uint256 amount, address to) public {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];

        // Effects
        user.rewardDebt -= int256(amount * accRewardPerShare / ACC_REWARD_PRECISION);
        user.amount -= amount;

        PSR.safeTransfer(to, amount);

        emit Withdraw(msg.sender, amount, to);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param to Receiver of rewards.
    function harvest(address to) public {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];
        int256 accumulatedReward = int256(user.amount * accRewardPerShare / ACC_REWARD_PRECISION);
        uint256 _pendingReward = uint256(accumulatedReward - user.rewardDebt);

        // Effects
        user.rewardDebt = accumulatedReward;

        // Interactions
        if (_pendingReward > 0) {
            minter.transfer(to, _pendingReward);
        }

        emit Harvest(msg.sender, _pendingReward);
    }

    /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and rewards.
    function withdrawAndHarvest(uint256 amount, address to) public {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];
        int256 accumulatedReward = int256(user.amount * accRewardPerShare / ACC_REWARD_PRECISION);
        uint256 _pendingReward = uint256(accumulatedReward - user.rewardDebt);

        // Effects
        user.rewardDebt = accumulatedReward - int256(amount * accRewardPerShare / ACC_REWARD_PRECISION);
        user.amount -= amount;

        // Interactions
        if (_pendingReward > 0) {
            minter.transfer(to, _pendingReward);
        }

        PSR.safeTransfer(to, amount);

        emit Withdraw(msg.sender, amount, to);
        emit Harvest(msg.sender, _pendingReward);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(address to) public {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        PSR.safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, amount, to);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice Sets the reward per second to be distributed. Can only be called by the owner.
    /// @param _rewardPerBlock The amount of reward to be distributed per second.
    function setRewardPerBlock(uint256 _rewardPerBlock) public onlyOwner {
        updatePool();
        rewardPerBlock = _rewardPerBlock;
        emit LogRewardPerBlock(_rewardPerBlock);
    }

    /* =============== EVENTS ==================== */

    event Deposit(address indexed user, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 amount);
    event LogUpdatePool(uint256 lastRewardBlock, uint256 lpSupply, uint256 accRewardPerShare);
    event LogRewardPerBlock(uint256 rewardPerBlock);
    event FundRescued(address indexed receiver, uint256 amount);
}