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
import {IStakingRewardsDual} from './IStakingRewardsDual.sol';

/**
 * @title  StakingRewardsDual.
 * @author MahaDAO.
 *
 * Original code written by:
 * - Travis Moore, Jason Huan, Same Kazemian, Sam Sun.
 *
 * Modified originally from Synthetixio
 * - https://raw.githubusercontent.com/Synthetixio/synthetix/develop/contracts/StakingRewards.sol
 */
contract StakingRewardsDual is IStakingRewardsDual, ReentrancyGuard, Pausable {
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
        uint256 multiplier; // 6 decimals of precision. 1x = 1000000.
    }

    IERC20 public _stakingToken;
    IERC20 public _rewardsToken0;
    IERC20 public _rewardsToken1;
    IARTH private _ARTH;
    IARTHController private _arthController;

    // This staking pool's percentage of the total ARTHX being distributed by all pools, 6 decimals of precision.
    uint256 public poolWeight0;
    // This staking pool's percentage of the total TOKEN 2 being distributed by all pools, 6 decimals of precision.
    uint256 public poolWeight1;

    // Max reward per second.
    uint256 public rewardRate0;
    uint256 public rewardRate1;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    // uint256 public rewardsDuration = 86400 hours;
    uint256 public rewardsDuration = 604800; // 7 * 86400  (7 days).
    uint256 public rewardPerTokenStored0 = 0;
    uint256 public rewardPerTokenStored1 = 0;

    uint256 public lockedStakeMinTime = 604800; // 7 * 86400  (7 days).
    uint256 public lockedStakeMaxMultiplier = 3000000; // 6 decimals of precision, 1x = 1000000.
    uint256 public lockedStakeTimeForMaxMultiplier = 3 * 365 * 86400; // 3 years.

    uint256 public crBoostMaxMultiplier = 1000000; // 6 decimals of precision. 1x = 1000000.

    bool public token1RewardsOn = false;
    bool public isUnlockedStaked; // Release lock stakes in case of system migration.

    address public ownerAddress;
    address public timelockAddress; // Governance timelock address

    uint256 private _stakingTokenSupply = 0;
    uint256 private _stakingTokenBoostedSupply = 0;
    uint256 private constant _PRICE_PRECISION = 1e6;
    uint256 private constant _MULTIPLIER_BASE = 1e6;

    string private _lockedStakeMinTimeStr = '604800'; // 7 days on genesis

    mapping(address => bool) public greylist;
    mapping(address => uint256) public rewards0;
    mapping(address => uint256) public rewards1;

    mapping(address => uint256) public userRewardPerTokenPaid0;
    mapping(address => uint256) public userRewardPerTokenPaid1;

    mapping(address => uint256) private _lockedBalances;
    mapping(address => uint256) private _boostedBalances;
    mapping(address => uint256) private _unlockedBalances;

    mapping(address => LockedStake[]) private _lockedStakes;

    /**
     * Modifier.
     */

    modifier updateReward(address account) {
        // Need to retro-adjust some things if the period hasn't been renewed, then start a new one
        if (block.timestamp > periodFinish) {
            _retroCatchUp();
        } else {
            (uint256 reward0, uint256 reward1) = rewardPerToken();
            rewardPerTokenStored0 = reward0;
            rewardPerTokenStored1 = reward1;
            lastUpdateTime = lastTimeRewardApplicable();
        }
        if (account != address(0)) {
            (uint256 earned0, uint256 earned1) = earned(account);
            rewards0[account] = earned0;
            rewards1[account] = earned1;
            userRewardPerTokenPaid0[account] = rewardPerTokenStored0;
            userRewardPerTokenPaid1[account] = rewardPerTokenStored1;
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
     * Events.
     */

    event RewardPaid(
        address indexed user,
        uint256 reward,
        address tokenAddress
    );
    event DefaultInitialization();
    event RewardAdded(uint256 reward);
    event LockedStakeMinTime(uint256 secs);
    event RewardsPeriodRenewed(address token);
    event MaxCRBoostMultiplier(uint256 multiplier);
    event Recovered(address token, uint256 amount);
    event RewardsDurationUpdated(uint256 newDuration);
    event Staked(address indexed user, uint256 amount);
    event LockedStakeTimeForMaxMultiplier(uint256 secs);
    event Withdrawn(address indexed user, uint256 amount);
    event LockedStakeMaxMultiplierUpdated(uint256 multiplier);
    event StakeLocked(address indexed user, uint256 amount, uint256 secs);
    event WithdrawnLocked(address indexed user, uint256 amount, bytes32 kekId);

    /**
     * Constructor.
     */
    constructor(
        address _owner,
        address __rewardsToken0,
        address __rewardsToken1,
        address __stakingToken,
        address _arthAddress,
        address _timelockAddress,
        uint256 _poolWeight0,
        uint256 _poolWeight1
    ) {
        ownerAddress = _owner;

        _ARTH = IARTH(_arthAddress);
        _stakingToken = IERC20(__stakingToken);
        _rewardsToken0 = IERC20(__rewardsToken0);
        _rewardsToken1 = IERC20(__rewardsToken1);

        poolWeight0 = _poolWeight0;
        poolWeight1 = _poolWeight1;
        lastUpdateTime = block.timestamp;
        timelockAddress = _timelockAddress;

        // 1000 ARTHX a day.
        rewardRate0 = (uint256(365000e18)).div(365 * 86400);
        rewardRate0 = rewardRate0.mul(poolWeight0).div(1e6);

        // ??? CRVDAO a day eventually.
        rewardRate1 = 0;
        rewardRate1 = rewardRate1.mul(poolWeight1).div(1e6);
        isUnlockedStaked = false;
    }

    /**
     * External.
     */

    function stake(uint256 amount)
        external
        override
        nonReentrant
        notPaused
        updateReward(msg.sender)
    {
        require(amount > 0, 'Cannot stake 0');
        require(greylist[msg.sender] == false, 'address has been greylisted');

        // Pull the tokens from the staker
        TransferHelper.safeTransferFrom(
            address(_stakingToken),
            msg.sender,
            address(this),
            amount
        );

        // Staking token supply and boosted supply
        _stakingTokenSupply = _stakingTokenSupply.add(amount);
        _stakingTokenBoostedSupply = _stakingTokenBoostedSupply.add(amount);

        // Staking token balance and boosted balance
        _unlockedBalances[msg.sender] = _unlockedBalances[msg.sender].add(
            amount
        );
        _boostedBalances[msg.sender] = _boostedBalances[msg.sender].add(amount);

        emit Staked(msg.sender, amount);
    }

    function stakeLocked(uint256 amount, uint256 secs)
        external
        override
        nonReentrant
        notPaused
        updateReward(msg.sender)
    {
        require(amount > 0, 'Cannot stake 0');
        require(secs > 0, 'Cannot wait for a negative number');
        require(greylist[msg.sender] == false, 'address has been greylisted');
        require(
            secs >= lockedStakeMinTime,
            StringHelpers.strConcat(
                'Minimum stake time not met (',
                _lockedStakeMinTimeStr,
                ')'
            )
        );
        require(
            secs <= lockedStakeTimeForMaxMultiplier,
            'You are trying to stake for too long'
        );

        uint256 multiplier = stakingMultiplier(secs);
        uint256 boostedAmount = amount.mul(multiplier).div(_PRICE_PRECISION);
        _lockedStakes[msg.sender].push(
            LockedStake(
                keccak256(
                    abi.encodePacked(msg.sender, block.timestamp, amount)
                ),
                block.timestamp,
                amount,
                block.timestamp.add(secs),
                multiplier
            )
        );

        // Pull the tokens from the staker
        TransferHelper.safeTransferFrom(
            address(_stakingToken),
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
        _lockedBalances[msg.sender] = _lockedBalances[msg.sender].add(amount);
        _boostedBalances[msg.sender] = _boostedBalances[msg.sender].add(
            boostedAmount
        );

        emit StakeLocked(msg.sender, amount, secs);
    }

    function totalSupply() external view override returns (uint256) {
        return _stakingTokenSupply;
    }

    function totalBoostedSupply() external view returns (uint256) {
        return _stakingTokenBoostedSupply;
    }

    function stakingMultiplier(uint256 secs) public view returns (uint256) {
        uint256 multiplier =
            uint256(_MULTIPLIER_BASE).add(
                secs.mul(lockedStakeMaxMultiplier.sub(_MULTIPLIER_BASE)).div(
                    lockedStakeTimeForMaxMultiplier
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
        return _stakingToken.decimals();
    }

    function rewardsFor(address account)
        external
        view
        returns (uint256, uint256)
    {
        // You may have use earned() instead, because of the order in which the contract executes
        return (rewards0[account], rewards1[account]);
    }

    function getRewardForDuration()
        external
        view
        override
        returns (uint256, uint256)
    {
        return (
            rewardRate0.mul(rewardsDuration).mul(crBoostMultiplier()).div(
                _PRICE_PRECISION
            ),
            rewardRate1.mul(rewardsDuration)
        );
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
        _stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
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
                isUnlockedStaked == true,
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
            _stakingToken.safeTransfer(msg.sender, theAmount);

            emit WithdrawnLocked(msg.sender, theAmount, kekId);
        }
    }

    function renewIfApplicable() external {
        if (block.timestamp > periodFinish) {
            _retroCatchUp();
        }
    }

    // Added to support recovering LP Rewards and other mistaken tokens from other systems to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyByOwnerOrGovernance
    {
        // Admin cannot withdraw the staking token from the contract
        require(tokenAddress != address(_stakingToken));

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
        uint256 _lockedStakeTimeForMaxMultiplier,
        uint256 _lockedStakeMinTime
    ) external onlyByOwnerOrGovernance {
        require(
            _lockedStakeTimeForMaxMultiplier >= 1,
            'Multiplier Max Time must be greater than or equal to 1'
        );
        require(
            _lockedStakeMinTime >= 1,
            'Multiplier Min Time must be greater than or equal to 1'
        );

        lockedStakeTimeForMaxMultiplier = _lockedStakeTimeForMaxMultiplier;

        lockedStakeMinTime = _lockedStakeMinTime;
        _lockedStakeMinTimeStr = StringHelpers.uint2str(_lockedStakeMinTime);

        emit LockedStakeTimeForMaxMultiplier(lockedStakeTimeForMaxMultiplier);
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
        isUnlockedStaked = !isUnlockedStaked;
    }

    function setARTHController(IARTHController controller)
        external
        onlyByOwnerOrGovernance
    {
        _arthController = controller;
    }


    function setRewardRates(uint256 _newRate0, uint256 _newRate1)
        external
        onlyByOwnerOrGovernance
    {
        rewardRate0 = _newRate0;
        rewardRate1 = _newRate1;
    }

    function toggleToken1Rewards() external onlyByOwnerOrGovernance {
        token1RewardsOn = !token1RewardsOn;
    }

    function setOwnerAndTimelock(address _newOwner, address _newTimelock)
        external
        onlyByOwnerOrGovernance
    {
        ownerAddress = _newOwner;
        timelockAddress = _newTimelock;
    }

    /**
     * Public.
     */

    function getReward() public override nonReentrant updateReward(msg.sender) {
        uint256 reward0 = rewards0[msg.sender];
        uint256 reward1 = rewards1[msg.sender];
        if (reward0 > 0) {
            rewards0[msg.sender] = 0;
            _rewardsToken0.transfer(msg.sender, reward0);
            emit RewardPaid(msg.sender, reward0, address(_rewardsToken0));
        }
        if (reward1 > 0) {
            rewards1[msg.sender] = 0;
            _rewardsToken1.transfer(msg.sender, reward1);
            emit RewardPaid(msg.sender, reward1, address(_rewardsToken1));
        }
    }

    // Total locked liquidity tokens
    function lockedBalanceOf(address account) public view returns (uint256) {
        return _lockedBalances[account];
    }

    function lastTimeRewardApplicable() public view override returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view override returns (uint256, uint256) {
        if (_stakingTokenSupply == 0) {
            return (rewardPerTokenStored0, rewardPerTokenStored1);
        } else {
            return (
                // Boosted emission
                rewardPerTokenStored0.add(
                    lastTimeRewardApplicable()
                        .sub(lastUpdateTime)
                        .mul(rewardRate0)
                        .mul(crBoostMultiplier())
                        .mul(1e18)
                        .div(_PRICE_PRECISION)
                        .div(_stakingTokenBoostedSupply)
                ),
                // Flat emission
                // Locked stakes will still get more weight with token1 rewards, but the CR boost will be canceled out for everyone
                rewardPerTokenStored1.add(
                    lastTimeRewardApplicable()
                        .sub(lastUpdateTime)
                        .mul(rewardRate1)
                        .mul(1e18)
                        .div(_stakingTokenBoostedSupply)
                )
            );
        }
    }

    function earned(address account)
        public
        view
        override
        returns (uint256, uint256)
    {
        (uint256 reward0, uint256 reward1) = rewardPerToken();
        return (
            _boostedBalances[account]
                .mul(reward0.sub(userRewardPerTokenPaid0[account]))
                .div(1e18)
                .add(rewards0[account]),
            _boostedBalances[account]
                .mul(reward1.sub(userRewardPerTokenPaid1[account]))
                .div(1e18)
                .add(rewards1[account])
        );
    }

    /**
     * Internal.
     */

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

        uint256 balance0 = _rewardsToken0.balanceOf(address(this));
        uint256 balance1 = _rewardsToken1.balanceOf(address(this));

        require(
            rewardRate0
                .mul(rewardsDuration)
                .mul(crBoostMultiplier())
                .mul(numPeriodsElapsed + 1)
                .div(_PRICE_PRECISION) <= balance0,
            'Not enough ARTHX available for rewards!'
        );

        if (token1RewardsOn) {
            require(
                rewardRate1.mul(rewardsDuration).mul(numPeriodsElapsed + 1) <=
                    balance1,
                'Not enough token1 available for rewards!'
            );
        }

        // uint256 old_lastUpdateTime = lastUpdateTime;
        // uint256 new_lastUpdateTime = block.timestamp;

        // lastUpdateTime = periodFinish;
        periodFinish = periodFinish.add(
            (numPeriodsElapsed.add(1)).mul(rewardsDuration)
        );

        (uint256 reward0, uint256 reward1) = rewardPerToken();
        rewardPerTokenStored0 = reward0;
        rewardPerTokenStored1 = reward1;
        lastUpdateTime = lastTimeRewardApplicable();

        emit RewardsPeriodRenewed(address(_stakingToken));
    }
}
