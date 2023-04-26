// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import { RewardsDistributionRecipient } from "../RewardsDistributionRecipient.sol";

//import "./ISaver.sol";
import "./StakeOrion.sol";

contract StakeOrionManager is
    ReentrancyGuard,
    Ownable,
    Pausable,
    RewardsDistributionRecipient
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    IERC20 public rewardsToken;
    address public orion;
    address public feeReceiver;
    uint256 decimals;
    uint256 public rewardFee = 13; // in %

    mapping(address => address) userContracts;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    address public poolManager;

    // for user gogo rewards
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 7 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stakingToken,
        uint256 _decimals,
        address _rewardsToken,
        address _orion,
        address _feeReceiver,
        address _rewardsDistribution
    ) {
        stakingToken = IERC20(_stakingToken);
        decimals = _decimals;
        orion = _orion;
        feeReceiver = _feeReceiver;
        rewardsToken = IERC20(_rewardsToken);
        rewardsDistribution = _rewardsDistribution;
    }

    function stake(uint256 amount)
        external
        nonReentrant
        updateReward(msg.sender)
    {
        // deploying new contract if not exist
        if (userContracts[msg.sender] == address(0)) {
            StakeOrion newContract = new StakeOrion(
                address(stakingToken),
                decimals,
                orion,
                msg.sender
            );
            userContracts[msg.sender] = address(newContract);
        }

        stakingToken.safeTransferFrom(
            msg.sender,
            userContracts[msg.sender],
            amount
        );

        _totalSupply += amount;
        _balances[msg.sender] += amount;

        StakeOrion(userContracts[msg.sender]).deposit(amount);
    }

    // if returned value > 0: amount is pending and has to be withdrawn later
    function withdraw(uint256 amount)
        public
        nonReentrant
        updateReward(msg.sender)
        returns (uint256)
    {
        if (amount > _balances[msg.sender]) {
            _totalSupply -= _balances[msg.sender];
            _balances[msg.sender] = 0;
        } else {
            _totalSupply -= amount;
            _balances[msg.sender] -= amount;
        }

        uint256 result = StakeOrion(userContracts[msg.sender]).withdraw(amount);
        return result;
    }

    function exit() external {
        withdraw(StakeOrion(userContracts[msg.sender]).getStakedBalance());
        getReward();
    }

    // if returned value > 0: amount is pending and has to be withdrawn later
    function getStableReward()
        external
        nonReentrant
        updateReward(msg.sender)
        returns (uint256)
    {
        return StakeOrion(userContracts[msg.sender]).getReward();
    }

    function withdrawPending() external nonReentrant updateReward(msg.sender) {
        StakeOrion(userContracts[msg.sender]).withdrawPending();
    }

    /* ========== REWARDS ========== */

    function getReward() public nonReentrant updateReward(msg.sender) {
        _getReward(msg.sender);
    }

    function getRewardFor(address user)
        external
        onlyPoolManager
        updateReward(user)
    {
        _getReward(user);
    }

    function _getReward(address user) internal {
        uint256 reward = rewards[user];
        if (reward > 0) {
            rewards[user] = 0;
            rewardsToken.safeTransfer(user, reward);
            emit RewardPaid(user, reward);
        }
    }

    function notifyRewardAmount(uint256 reward)
        external
        override
        onlyRewardsDistribution
        updateReward(address(0))
    {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(
            rewardRate <= balance.div(rewardsDuration),
            "Provided reward too high"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier onlyPoolManager() {
        require(
            msg.sender == poolManager,
            "The function can be called only by the PoolManager"
        );
        _;
    }

    /* ========== VIEWS ========== */

    function getUserContract(address user) external view returns (address) {
        return userContracts[user];
    }

    function getPending(address user) external view returns (bool) {
        return StakeOrion(userContracts[user]).pending();
    }

    function getPendingAmount(address user) external view returns (uint256) {
        return StakeOrion(userContracts[user]).pendingAmount();
    }

    function getContractBalance(address user) external view returns (uint256) {
        return StakeOrion(userContracts[user]).getContractBalance();
    }

    function getStakedBalance(address user) public view returns (uint256) {
        return StakeOrion(userContracts[user]).getStakedBalance();
    }

    function earnedStable(address user) public view returns (uint256) {
        return StakeOrion(userContracts[user]).earned();
    }

    // for gogo rewards
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(_totalSupply)
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            _balances[account]
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    function rewardsClaimableWithoutLoss(address account)
        public
        view
        returns (uint256)
    {
        return earned(account);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== ADMIN ========== */

    function setFeeReceiver(address newFeeReceiver) external onlyOwner {
        feeReceiver = newFeeReceiver;
    }

    function setRewardsDistributionAddress(address rewardsDistributionAddress)
        external
        onlyOwner
    {
        rewardsDistribution = rewardsDistributionAddress;
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(periodFinish == 0 || block.timestamp > periodFinish, "period");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setFee(uint256 fee) external onlyOwner {
        require(fee <= 100, "fee cannot be bigger than 100%");
        rewardFee = fee;
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setPoolManager(address poolManager_) external onlyOwner {
        poolManager = poolManager_;
        emit PoolManagerSet(poolManager);
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event PoolManagerSet(address poolManager);
}
