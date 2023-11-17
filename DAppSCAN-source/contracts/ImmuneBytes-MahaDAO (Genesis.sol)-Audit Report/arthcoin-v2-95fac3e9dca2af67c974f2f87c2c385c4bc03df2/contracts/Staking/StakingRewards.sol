// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {Math} from '../utils/math/Math.sol';
import {Pausable} from './Pausable.sol';
import {IARTH} from '../Arth/IARTH.sol';
import {IERC20} from '../ERC20/IERC20.sol';
import {SafeMath} from '../utils/math/SafeMath.sol';
import {SafeERC20} from '../ERC20/SafeERC20.sol';
import {IStakingRewards} from './IStakingRewards.sol';
import {StringHelpers} from '../utils/StringHelpers.sol';
import {IARTHController} from '../Arth/IARTHController.sol';
import {ReentrancyGuard} from '../utils/ReentrancyGuard.sol';
import {TransferHelper} from '../Uniswap/TransferHelper.sol';
import {AccessControl} from '../access/AccessControl.sol';
import {RewardsDistributionRecipient} from './RewardsDistributionRecipient.sol';

/**
 * @title  StakingRewards.
 * @author MahaDAO.
 *
 * Original code written by:
 * - Travis Moore, Jason Huan, Same Kazemian, Sam Sun.
 *
 * Modified originally from Synthetixio
 * https://raw.githubusercontent.com/Synthetixio/synthetix/develop/contracts/StakingRewards.sol
 */
contract StakingRewards is
    AccessControl,
    IStakingRewards,
    RewardsDistributionRecipient,
    ReentrancyGuard,
    Pausable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /**
     * State variables.
     */

    struct LockedStake {
        bytes32 kekId;
        uint256 startTimestamp;
        uint256 amount;
        uint256 endingTimestamp;
        uint256 multiplier; // 6 decimals of precision. 1x = 1000000
    }

    IERC20 public immutable rewardsToken;
    IERC20 public immutable stakingToken;
    IARTH private _ARTH;
    IARTHController private _arthController;

    // This staking pool's percentage of the total ARTHX being distributed by all pools, 6 decimals of precision
    uint256 public immutable poolWeight;
    // Max reward per second
    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored = 0;
    // uint256 public rewardsDuration = 86400 hours;
    uint256 public rewardsDuration = 7 days;

    uint256 public lockedStakeMinTime = 7 days;
    string private lockedStakeMinTimeStr = '604800'; // 7 days on genesis
    uint256 public lockedStakeMaxMultiplier = 3e6; // 6 decimals of precision. 1x = 1000000
    uint256 public lockedStakeTimeGorMaxMultiplier = 3 * 365 days; // 3 years

    address public ownerAddress;
    address public timelockAddress; // Governance timelock address

    uint256 private _stakingTokenSupply = 0;
    uint256 private _stakingTokenBoostedSupply = 0;

    bool public isLockedStakes; // Release lock stakes in case of system migration

    uint256 private constant _PRICE_PRECISION = 1e6;
    uint256 private constant _MULTIPLIER_BASE = 1e6;
    bytes32 private constant _POOL_ROLE = keccak256('_POOL_ROLE');

    uint256 public crBoostMaxMultiplier = 3e6; // 6 decimals of precision. 1x = 1000000

    mapping(address => bool) public greylist;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public userRewardPerTokenPaid;

    mapping(address => uint256) private _lockedBalances;
    mapping(address => uint256) private _boostedBalances;
    mapping(address => uint256) private _unlockedBalances;
    mapping(address => LockedStake[]) private _lockedStakes;

    /**
     * Events.
     */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event StakeLocked(address indexed user, uint256 amount, uint256 secs);
    event Withdrawn(address indexed user, uint256 amount);
    event WithdrawnLocked(address indexed user, uint256 amount, bytes32 kekId);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event RewardsPeriodRenewed(address token);
    event DefaultInitialization();
    event LockedStakeMaxMultiplierUpdated(uint256 multiplier);
    event LockedStakeTimeForMaxMultiplier(uint256 secs);
    event LockedStakeMinTime(uint256 secs);
    event MaxCRBoostMultiplier(uint256 multiplier);

    /**
     * Modifier.
     */

    modifier onlyPool {
        require(hasRole(_POOL_ROLE, msg.sender), 'Staking: FORBIDDEN');
        _;
    }

    modifier updateReward(address account) {
        // Need to retro-adjust some things if the period hasn't been renewed, then start a new one
        if (block.timestamp > periodFinish) {
            _retroCatchUp();
        } else {
            rewardPerTokenStored = rewardPerToken();
            lastUpdateTime = lastTimeRewardApplicable();
        }
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == ownerAddress || msg.sender == timelockAddress,
            'You are not the owner or the governance timelock'
        );
        _;
    }

    /**
     * Constructor.
     */

    constructor(
        address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        address _arthAddress,
        address _timelockAddress,
        uint256 _poolWeight
    ) {
        ownerAddress = _owner;
        _ARTH = IARTH(_arthAddress);
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);

        poolWeight = _poolWeight;
        lastUpdateTime = block.timestamp;
        timelockAddress = _timelockAddress;
        rewardsDistribution = _rewardsDistribution;

        isLockedStakes = false;
        rewardRate = 380517503805175038; // (uint256(12000000e18)).div(365 * 86400); // Base emission rate of 12M ARTHX over the first year
        rewardRate = rewardRate.mul(_poolWeight).div(1e6);

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(_POOL_ROLE, _msgSender());
    }

    /**
     * External.
     */

    function stakeLockedFor(
        address who,
        uint256 amount,
        uint256 duration
    ) external override onlyPool {
        _stakeLocked(who, amount, duration);
    }

    function setArthController(address _controller)
        external
        onlyByOwnerOrGovernance
    {
        _arthController = IARTHController(_controller);
    }

    function withdraw(uint256 amount)
        external
        override
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, 'Cannot withdraw 0');

        // Staking token balance and boosted balance
        _unlockedBalances[msg.sender] = _unlockedBalances[msg.sender].sub(
            amount
        );
        _boostedBalances[msg.sender] = _boostedBalances[msg.sender].sub(amount);

        // Staking token supply and boosted supply
        _stakingTokenSupply = _stakingTokenSupply.sub(amount);
        _stakingTokenBoostedSupply = _stakingTokenBoostedSupply.sub(amount);

        // Give the tokens to the withdrawer
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function renewIfApplicable() external {
        if (block.timestamp > periodFinish) {
            _retroCatchUp();
        }
    }

    function withdrawLocked(bytes32 kekId)
        external
        override
        nonReentrant
        updateReward(msg.sender)
    {
        LockedStake memory thisStake;
        thisStake.amount = 0;
        uint256 theIndex;
        for (uint256 i = 0; i < _lockedStakes[msg.sender].length; i++) {
            if (kekId == _lockedStakes[msg.sender][i].kekId) {
                thisStake = _lockedStakes[msg.sender][i];
                theIndex = i;
                break;
            }
        }
        require(thisStake.kekId == kekId, 'Stake not found');
        require(
            block.timestamp >= thisStake.endingTimestamp ||
                isLockedStakes == true,
            'Stake is still locked!'
        );

        uint256 theAmount = thisStake.amount;
        uint256 boostedAmount =
            theAmount.mul(thisStake.multiplier).div(_PRICE_PRECISION);
        if (theAmount > 0) {
            // Staking token balance and boosted balance
            _lockedBalances[msg.sender] = _lockedBalances[msg.sender].sub(
                theAmount
            );
            _boostedBalances[msg.sender] = _boostedBalances[msg.sender].sub(
                boostedAmount
            );

            // Staking token supply and boosted supply
            _stakingTokenSupply = _stakingTokenSupply.sub(theAmount);
            _stakingTokenBoostedSupply = _stakingTokenBoostedSupply.sub(
                boostedAmount
            );

            // Remove the stake from the array
            delete _lockedStakes[msg.sender][theIndex];

            // Give the tokens to the withdrawer
            stakingToken.safeTransfer(msg.sender, theAmount);

            emit WithdrawnLocked(msg.sender, theAmount, kekId);
        }
    }

    // Added to support recovering LP Rewards from other systems to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyByOwnerOrGovernance
    {
        // Admin cannot withdraw the staking token from the contract
        require(tokenAddress != address(stakingToken));

        IERC20(tokenAddress).transfer(ownerAddress, tokenAmount);

        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(uint256 _rewardsDuration)
        external
        onlyByOwnerOrGovernance
    {
        require(
            periodFinish == 0 || block.timestamp > periodFinish,
            'Previous rewards period must be complete before changing the duration for the new period'
        );

        rewardsDuration = _rewardsDuration;

        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setMultipliers(
        uint256 _lockedStakeMaxMultiplier,
        uint256 _crBoostMaxMultiplier
    ) external onlyByOwnerOrGovernance {
        require(
            _lockedStakeMaxMultiplier >= 1,
            'Multiplier must be greater than or equal to 1'
        );
        require(
            _crBoostMaxMultiplier >= 1,
            'Max CR Boost must be greater than or equal to 1'
        );

        lockedStakeMaxMultiplier = _lockedStakeMaxMultiplier;
        crBoostMaxMultiplier = _crBoostMaxMultiplier;

        emit MaxCRBoostMultiplier(crBoostMaxMultiplier);
        emit LockedStakeMaxMultiplierUpdated(lockedStakeMaxMultiplier);
    }

    function setLockedStakeTimeForMinAndMaxMultiplier(
        uint256 _lockedStakeTimeGorMaxMultiplier,
        uint256 _lockedStakeMinTime
    ) external onlyByOwnerOrGovernance {
        require(
            _lockedStakeTimeGorMaxMultiplier >= 1,
            'Multiplier Max Time must be greater than or equal to 1'
        );
        require(
            _lockedStakeMinTime >= 1,
            'Multiplier Min Time must be greater than or equal to 1'
        );

        lockedStakeTimeGorMaxMultiplier = _lockedStakeTimeGorMaxMultiplier;

        lockedStakeMinTime = _lockedStakeMinTime;
        lockedStakeMinTimeStr = StringHelpers.uint2str(_lockedStakeMinTime);

        emit LockedStakeTimeForMaxMultiplier(lockedStakeTimeGorMaxMultiplier);
        emit LockedStakeMinTime(_lockedStakeMinTime);
    }

    function initializeDefault() external onlyByOwnerOrGovernance {
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);

        emit DefaultInitialization();
    }

    function greylistAddress(address _address)
        external
        onlyByOwnerOrGovernance
    {
        greylist[_address] = !(greylist[_address]);
    }

    function unlockStakes() external onlyByOwnerOrGovernance {
        isLockedStakes = !isLockedStakes;
    }

    function setRewardRate(uint256 _newRate) external onlyByOwnerOrGovernance {
        rewardRate = _newRate;
    }

    function setOwnerAndTimelock(address _newOwner, address _newTimelock)
        external
        onlyByOwnerOrGovernance
    {
        ownerAddress = _newOwner;
        timelockAddress = _newTimelock;
    }

    function stakeFor(address who, uint256 amount) external override onlyPool {
        _stake(who, amount);
    }

    function stake(uint256 amount) external override {
        _stake(msg.sender, amount);
    }

    function stakeLocked(uint256 amount, uint256 secs) external override {
        _stakeLocked(msg.sender, amount, secs);
    }

    function totalSupply() external view override returns (uint256) {
        return _stakingTokenSupply;
    }

    function totalBoostedSupply() external view returns (uint256) {
        return _stakingTokenBoostedSupply;
    }

    // Total unlocked and locked liquidity tokens
    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return (_unlockedBalances[account]).add(_lockedBalances[account]);
    }

    // Total unlocked liquidity tokens
    function unlockedBalanceOf(address account)
        external
        view
        returns (uint256)
    {
        return _unlockedBalances[account];
    }

    // Total 'balance' used for calculating the percent of the pool the account owns
    // Takes into account the locked stake time multiplier
    function boostedBalanceOf(address account) external view returns (uint256) {
        return _boostedBalances[account];
    }

    function _lockedStakesOf(address account)
        external
        view
        returns (LockedStake[] memory)
    {
        return _lockedStakes[account];
    }

    function stakingDecimals() external view returns (uint256) {
        return stakingToken.decimals();
    }

    function rewardsFor(address account) external view returns (uint256) {
        // You may have use earned() instead, because of the order in which the contract executes
        return rewards[account];
    }

    function getRewardForDuration() external view override returns (uint256) {
        return
            rewardRate.mul(rewardsDuration).mul(crBoostMultiplier()).div(
                _PRICE_PRECISION
            );
    }

    /**
     * Public
     */

    function stakingMultiplier(uint256 secs) public view returns (uint256) {
        uint256 multiplier =
            uint256(_MULTIPLIER_BASE).add(
                secs.mul(lockedStakeMaxMultiplier.sub(_MULTIPLIER_BASE)).div(
                    lockedStakeTimeGorMaxMultiplier
                )
            );
        if (multiplier > lockedStakeMaxMultiplier)
            multiplier = lockedStakeMaxMultiplier;
        return multiplier;
    }

    function crBoostMultiplier() public view returns (uint256) {
        uint256 multiplier =
            uint256(_MULTIPLIER_BASE).add(
                (
                    uint256(_MULTIPLIER_BASE).sub(
                        _arthController.getGlobalCollateralRatio()
                    )
                )
                    .mul(crBoostMaxMultiplier.sub(_MULTIPLIER_BASE))
                    .div(_MULTIPLIER_BASE)
            );
        return multiplier;
    }

    // Total locked liquidity tokens
    function lockedBalanceOf(address account) external view returns (uint256) {
        return _lockedBalances[account];
    }

    function lastTimeRewardApplicable() public view override returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view override returns (uint256) {
        if (_stakingTokenSupply == 0) {
            return rewardPerTokenStored;
        } else {
            return
                rewardPerTokenStored.add(
                    lastTimeRewardApplicable()
                        .sub(lastUpdateTime)
                        .mul(rewardRate)
                        .mul(crBoostMultiplier())
                        .mul(1e18)
                        .div(_PRICE_PRECISION)
                        .div(_stakingTokenBoostedSupply)
                );
        }
    }

    function getReward() external override nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function earned(address account) public view override returns (uint256) {
        return
            _boostedBalances[account]
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    /**
     * Internal.
     */

    function _stake(address who, uint256 amount)
        internal
        nonReentrant
        notPaused
        updateReward(who)
    {
        require(amount > 0, 'Cannot stake 0');
        require(greylist[who] == false, 'address has been greylisted');

        // Pull the tokens from the staker
        TransferHelper.safeTransferFrom(
            address(stakingToken),
            msg.sender,
            address(this),
            amount
        );

        // Staking token supply and boosted supply
        _stakingTokenSupply = _stakingTokenSupply.add(amount);
        _stakingTokenBoostedSupply = _stakingTokenBoostedSupply.add(amount);

        // Staking token balance and boosted balance
        _unlockedBalances[who] = _unlockedBalances[who].add(amount);
        _boostedBalances[who] = _boostedBalances[who].add(amount);

        emit Staked(who, amount);
    }

    function _stakeLocked(
        address who,
        uint256 amount,
        uint256 secs
    ) internal nonReentrant notPaused updateReward(who) {
        require(amount > 0, 'Cannot stake 0');
        require(secs > 0, 'Cannot wait for a negative number');
        require(greylist[who] == false, 'address has been greylisted');
        require(
            secs >= lockedStakeMinTime,
            StringHelpers.strConcat(
                'Minimum stake time not met (',
                lockedStakeMinTimeStr,
                ')'
            )
        );
        require(
            secs <= lockedStakeTimeGorMaxMultiplier,
            'You are trying to stake for too long'
        );

        uint256 multiplier = stakingMultiplier(secs);
        uint256 boostedAmount = amount.mul(multiplier).div(_PRICE_PRECISION);
        _lockedStakes[who].push(
            LockedStake(
                keccak256(abi.encodePacked(who, block.timestamp, amount)),
                block.timestamp,
                amount,
                block.timestamp.add(secs),
                multiplier
            )
        );

        // Pull the tokens from the staker or the operator
        TransferHelper.safeTransferFrom(
            address(stakingToken),
            msg.sender,
            address(this),
            amount
        );

        // Staking token supply and boosted supply
        _stakingTokenSupply = _stakingTokenSupply.add(amount);
        _stakingTokenBoostedSupply = _stakingTokenBoostedSupply.add(
            boostedAmount
        );

        // Staking token balance and boosted balance
        _lockedBalances[who] = _lockedBalances[who].add(amount);
        _boostedBalances[who] = _boostedBalances[who].add(boostedAmount);

        emit StakeLocked(who, amount, secs);
    }

    // If the period expired, renew it
    function _retroCatchUp() internal {
        // Failsafe check
        require(block.timestamp > periodFinish, 'Period has not expired yet!');

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 numPeriodsElapsed =
            uint256(block.timestamp.sub(periodFinish)) / rewardsDuration; // Floor division to the nearest period
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(
            rewardRate
                .mul(rewardsDuration)
                .mul(crBoostMultiplier())
                .mul(numPeriodsElapsed + 1)
                .div(_PRICE_PRECISION) <= balance,
            'Not enough ARTHX available for rewards!'
        );

        // uint256 old_lastUpdateTime = lastUpdateTime;
        // uint256 new_lastUpdateTime = block.timestamp;

        // lastUpdateTime = periodFinish;
        periodFinish = periodFinish.add(
            (numPeriodsElapsed.add(1)).mul(rewardsDuration)
        );

        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        emit RewardsPeriodRenewed(address(stakingToken));
    }

    /*
    // This notifies people that the reward is being changed
    function notifyRewardAmount(uint256 reward) external override onlyRewardsDistribution updateReward(address(0)) {
        // Needed to make compiler happy


        // if (block.timestamp >= periodFinish) {
        //     rewardRate = reward.mul(crBoostMultiplier()).div(rewardsDuration).div(_PRICE_PRECISION);
        // } else {
        //     uint256 remaining = periodFinish.sub(block.timestamp);
        //     uint256 leftover = remaining.mul(rewardRate);
        //     rewardRate = reward.mul(crBoostMultiplier()).add(leftover).div(rewardsDuration).div(_PRICE_PRECISION);
        // }

        // // Ensure the provided reward amount is not more than the balance in the contract.
        // // This keeps the reward rate in the right range, preventing overflows due to
        // // very high values of rewardRate in the earned and rewardsPerToken functions;
        // // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        // uint balance = rewardsToken.balanceOf(address(this));
        // require(rewardRate <= balance.div(rewardsDuration), "Provided reward too high");

        // lastUpdateTime = block.timestamp;
        // periodFinish = block.timestamp.add(rewardsDuration);
        // emit RewardAdded(reward);
    }
    */
}
