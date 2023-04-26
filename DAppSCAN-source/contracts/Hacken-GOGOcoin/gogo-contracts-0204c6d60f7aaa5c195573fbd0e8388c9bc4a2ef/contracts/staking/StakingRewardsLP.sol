// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.4;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Inheritance
import { RewardsDistributionRecipient } from "./RewardsDistributionRecipient.sol";
import { IGoGoNFTOracle } from "../nftBoosting/IGoGoNFTOracle.sol";

contract StakingRewardsLP is
    RewardsDistributionRecipient,
    ReentrancyGuard,
    Ownable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable rewardsToken;
    IERC20 public immutable stakingToken;
    IERC721 public boostNFTToken;
    IGoGoNFTOracle public gogoNFTOracle;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 60 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public constant lockPeriod = 60 days;
    uint256 public totalStakers = 0;
    uint256 public performanceFee = 15;
    address public buybackAddress;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public lastStakedTime;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _originalBalances;
    mapping(address => uint256) private _stakedNft;

    address public poolManager;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        address _buybackAddress
    ) {
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;
        buybackAddress = _buybackAddress;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
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
        if (lastStakedTime[account].add(lockPeriod) < block.timestamp) {
            return earned(account);
        } else {
            return 0;
        }
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount)
        external
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot stake 0");
        uint256 boostAmount = amount;
        if (_stakedNft[msg.sender] != 0) {
            boostAmount = amount
            .mul(gogoNFTOracle.getBoostMultiplyer(_stakedNft[msg.sender]))
            .div(10);
        }
        _totalSupply = _totalSupply.add(boostAmount);
        if (_balances[msg.sender] == 0) totalStakers = totalStakers.add(1);
        _balances[msg.sender] = _balances[msg.sender].add(boostAmount);
        _originalBalances[msg.sender] = _originalBalances[msg.sender].add(
            amount
        );
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        lastStakedTime[msg.sender] = block.timestamp;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot withdraw 0");
        uint256 boostAmount = amount;
        if (_stakedNft[msg.sender] != 0) {
            boostAmount = amount
            .mul(gogoNFTOracle.getBoostMultiplyer(_stakedNft[msg.sender]))
            .div(10);
        }

        _totalSupply = _totalSupply.sub(boostAmount);
        _balances[msg.sender] = _balances[msg.sender].sub(boostAmount);
        _originalBalances[msg.sender] = _originalBalances[msg.sender].sub(
            amount
        );
        if (_balances[msg.sender] == 0) {
            totalStakers = totalStakers.sub(1);
            if (_stakedNft[msg.sender] > 0) unstakeNFT();
        }
        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        require(
            lastStakedTime[msg.sender].add(lockPeriod) < block.timestamp,
            "Claim not possible in lock period"
        );
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            uint256 fee = reward.mul(performanceFee).div(100);
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward.sub(fee));
            rewardsToken.safeTransfer(buybackAddress, fee);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function getRewardByLoss() public nonReentrant updateReward(msg.sender) {
        require(
            lastStakedTime[msg.sender].add(lockPeriod) > block.timestamp,
            "Claim by loss not possible in after lock period"
        );
        uint256 reward = rewards[msg.sender];
        uint256 userReward = reward.div(2);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, userReward);
            rewardsToken.safeTransfer(buybackAddress, reward.sub(userReward));
            emit RewardPaid(msg.sender, userReward);
        }
    }

    function getRewardFor(address account)
        external
        nonReentrant
        onlyPoolManager
        updateReward(account)
    {
        // not checking the lockPeriod because PoolManager calls this for unlocked pool only
        uint256 reward = rewards[account];
        if (reward > 0) {
            uint256 fee = reward.mul(performanceFee).div(100);
            rewards[account] = 0;
            rewardsToken.safeTransfer(account, reward.sub(fee));
            rewardsToken.safeTransfer(buybackAddress, fee);
            emit RewardPaid(account, reward);
        }
    }

    function exit() external {
        withdraw(_originalBalances[msg.sender]);
        getReward();
    }

    function exitByLoss() external {
        withdraw(_balances[msg.sender]);
        getRewardByLoss();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

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

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(periodFinish == 0 || block.timestamp > periodFinish, "period");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setNftParams(address _nftOracle, address _nftToken)
        public
        onlyOwner
    {
        boostNFTToken = IERC721(_nftToken);
        gogoNFTOracle = IGoGoNFTOracle(_nftOracle);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        require(
            tokenAddress != address(stakingToken),
            "Cannot withdraw the staking token"
        );
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    // PoolManager is set only here, doing it in constructor seems limiting
    function setPoolManager(address poolManager_) external onlyOwner {
        poolManager = poolManager_;
        emit PoolManagerSet(poolManager);
    }

    function stakeNFT(uint256 tokenId) external updateReward(msg.sender) {
        require(block.timestamp < periodFinish, "user cannot stake nft");
        require(_stakedNft[msg.sender] == 0, "NFT is already staked");
        require(_balances[msg.sender] > 0, "Please stake token first");

        _stakedNft[msg.sender] = tokenId;
        boostNFTToken.transferFrom(msg.sender, address(this), tokenId);

        _balances[msg.sender] = _balances[msg.sender]
        .mul(gogoNFTOracle.getBoostMultiplyer(tokenId))
        .div(10);

        _totalSupply = _totalSupply.sub(_originalBalances[msg.sender]).add(
            _balances[msg.sender]
        );
    }

    function unstakeNFT() internal {
        boostNFTToken.transferFrom(
            address(this),
            msg.sender,
            _stakedNft[msg.sender]
        );
        _totalSupply = _totalSupply.add(_originalBalances[msg.sender]).sub(
            _balances[msg.sender]
        );
        _balances[msg.sender] = _originalBalances[msg.sender];
        delete _stakedNft[msg.sender];
    }

    // performance fee in %
    function setPerformanceFee(uint256 performanceFee_) external onlyOwner {
        require(performanceFee_ <= 100, "performance fee too high");
        performanceFee = performanceFee_;
        emit PerformanceFeeSet(performanceFee);
    }

    function setRewardsDistributionAddress(address newDistributionAddress)
        external
        onlyOwner
    {
        rewardsDistribution = newDistributionAddress;
    }

    function setBuybackAddress(address newBuybackAddress) external onlyOwner {
        buybackAddress = newBuybackAddress;
    }

    /* ========== MODIFIERS ========== */

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

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event PoolManagerSet(address poolManager);
    event PerformanceFeeSet(uint256 performanceFee);
}
