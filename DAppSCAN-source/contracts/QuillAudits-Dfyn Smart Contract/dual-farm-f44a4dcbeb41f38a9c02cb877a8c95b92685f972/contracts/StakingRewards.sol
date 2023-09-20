// SPDX-License-Identifier: MIT
// SWC-102-Outdated Compiler Version: L4
// SWC-103-Floating Pragma: L4
pragma solidity >=0.6.11;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libraries/NativeMetaTransaction/NativeMetaTransaction.sol";

// Inheritance
import "./interfaces/IStakingRewards.sol";
import "./RewardsDistributionRecipient.sol";

contract StakingRewards is
    IStakingRewards,
    RewardsDistributionRecipient,
    ReentrancyGuard,
    NativeMetaTransaction
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IERC20 public stakingToken;
    uint256 public periodFinish = 0;
    uint256 public rewardsDuration = 30 days;
    uint256 public rewardPerTokenStored;
    uint256 private _totalSupply;
    address[] private stakers;
    address[] public rewardTokens;

    mapping(address => uint256) public rewardsPerTokenMap;
    mapping(address => uint256) public tokenRewardRate;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) public rewardLastUpdatedTime;
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public rewards;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _rewardsDistribution,
        address[] memory _rewardTokens,
        address _stakingToken
    ) public {
        rewardTokens = _rewardTokens;
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;

        _initializeEIP712("DualFarmsV1");
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function stakerBalances()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 stakerCount = stakers.length;
        uint256[] memory balances = new uint256[](stakerCount);
        for (uint256 i = 0; i < stakers.length; i++) {
            balances[i] = _balances[stakers[i]];
        }
        return (stakers, balances);
    }

    // SWC-120-Weak Sources of Randomness from Chain Attributes: L87
    function lastTimeRewardApplicable() public view override returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken(address rewardToken)
        public
        view
        override
        returns (uint256)
    {
        if (_totalSupply == 0) {
            return rewardsPerTokenMap[rewardToken];
        }
        return
            rewardsPerTokenMap[rewardToken].add(
                lastTimeRewardApplicable()
                    .sub(rewardLastUpdatedTime[rewardToken])
                    .mul(tokenRewardRate[rewardToken])
                    .mul(1e18)
                    .div(_totalSupply)
            );
    }

    function earned(address account, address rewardToken)
        public
        view
        override
        returns (uint256)
    {
        return
            _balances[account]
                .mul(
                rewardPerToken(rewardToken).sub(
                    userRewardPerTokenPaid[account][rewardToken]
                )
            )
                .div(1e18)
                .add(rewards[account][rewardToken]);
    }

    function getRewardForDuration(address rewardToken)
        external
        view
        override
        returns (uint256)
    {
        return tokenRewardRate[rewardToken].mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stakeWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant updateReward(_msgSender()) {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[_msgSender()] = _balances[_msgSender()].add(amount);

        // permit
        IEllipticRC20(address(stakingToken)).permit(
            _msgSender(),
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );

        stakingToken.safeTransferFrom(_msgSender(), address(this), amount);
        emit Staked(_msgSender(), amount);
    }

    function stake(uint256 amount)
        external
        override
        nonReentrant
        updateReward(_msgSender())
    {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        if (_balances[_msgSender()] == 0) {
            stakers.push(_msgSender());
        }
        _balances[_msgSender()] = _balances[_msgSender()].add(amount);
        stakingToken.safeTransferFrom(_msgSender(), address(this), amount);
        emit Staked(_msgSender(), amount);
    }

    function withdraw(uint256 amount)
        public
        override
        nonReentrant
        updateReward(_msgSender())
    {
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[_msgSender()] = _balances[_msgSender()].sub(amount);
        stakingToken.safeTransfer(_msgSender(), amount);
        emit Withdrawn(_msgSender(), amount);
    }

    function getReward()
        public
        override
        nonReentrant
        updateReward(_msgSender())
    {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 reward = rewards[_msgSender()][rewardTokens[i]];
            if (reward > 0) {
                rewards[_msgSender()][rewardTokens[i]] = 0;
                IERC20(rewardTokens[i]).safeTransfer(_msgSender(), reward);
                emit RewardPaid(_msgSender(), reward);
            }
        }
    }

    function exit() external override {
        withdraw(_balances[_msgSender()]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(address rewardToken, uint256 reward)
        external
        override
        onlyRewardsDistribution
        updateReward(address(0))
    {
        // SWC-120-Weak Sources of Randomness from Chain Attributes: L223, L225, L227
        uint256 rewardRate = tokenRewardRate[rewardToken];
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
            periodFinish = block.timestamp.add(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(remaining);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        // SWC-120-Weak Sources of Randomness from Chain Attributes: L239
        require(
            rewardRate <= balance.div(periodFinish.sub(block.timestamp)),
            "Provided reward too high"
        );

        // SWC-120-Weak Sources of Randomness from Chain Attributes: 244
        rewardLastUpdatedTime[rewardToken] = block.timestamp;
        tokenRewardRate[rewardToken] = rewardRate;
        emit RewardAdded(reward);
    }

    function rescueFunds(address tokenAddress, address receiver)
        external
        onlyRewardsDistribution
    {
        require(
            tokenAddress != address(stakingToken),
            "StakingRewards: rescue of staking token not allowed"
        );
        IERC20(tokenAddress).transfer(
            receiver,
            IERC20(tokenAddress).balanceOf(address(this))
        );
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            rewardsPerTokenMap[rewardTokens[i]] = rewardPerToken(
                rewardTokens[i]
            );
            rewardLastUpdatedTime[rewardTokens[i]] = lastTimeRewardApplicable();
            if (account != address(0)) {
                rewards[account][rewardTokens[i]] = earned(
                    account,
                    rewardTokens[i]
                );
                userRewardPerTokenPaid[account][
                    rewardTokens[i]
                ] = rewardsPerTokenMap[rewardTokens[i]];
            }
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}

interface IEllipticRC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
