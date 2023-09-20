// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
/**
 * @title GreenHouse staking contract
 * @dev A stakable smart contract that stores ERC20 trusted token.
 */
contract GreenHouse is Ownable {
    // Staking ERC20 trustedToken
    IERC20 public trustedToken;

    // All Users Stakes
    uint256 public allStakes = 0;
    uint256 public everStakedUsersCount = 0;

    // Bonus and Monthly Reward Pools
    uint256 public bonusRewardPool = 0;  // Bonus Reward Pool
    uint256 public monthlyRewardPool = 0;  // Monthly Reward Pool
    mapping(address => uint256) public referralRewards;

    // Users stakes, withdrawals and users that has staked at least once
    mapping(address => uint256) internal _stakes;
    mapping(address => uint256) internal _withdrawals;
    mapping(address => bool) internal _hasStaked;

    // Reward calculation magic
    uint256 constant internal MAGNITUDE = 2**128;

    uint256 internal _magnifiedRewardPerStake = 0;
    mapping(address => int256) internal _magnifiedRewardCorrections;

    // Staking and Unstaking fees
    uint256 constant internal FEE_ALL_USERS_STAKED_PERMILLE = 700;
    uint256 constant internal FEE_BONUS_POOL_PERMILLE = 100;
    uint256 constant internal FEE_PLATFORM_WALLET_PERMILLE = 100;
    uint256 constant internal TOKEN_DECIMAL=10**8;
    uint256 constant internal FEE_REFERRAL_PERMILLE = 50;
    uint256 constant internal FEE_PARTNER_WALLET_PERMILLE = 50;

    // Monthly Pool distribution and timer
    uint256 constant internal MONTHLY_POOL_DISTRIBUTE_ALL_USERS_PERCENT = 50;
    uint256 constant internal MONYHLY_POOL_TIMER = 86400; // 30 days  =2592000
    uint256 internal _monthlyPoolLastDistributedAt=0;

    // Bonus Pool distribution
    uint256 constant internal BONUS_POOL_DISTRIBUTE_ALL_USERS_PERCENT = 40;
    uint256 constant internal BONUS_POOL_DISTRIBUTE_LEADERBOARD_PERCENT = 40;

    // Bonus Pool Leaderboard queue
    mapping(uint256 => address) internal _bonusPoolLeaderboard;
    mapping(address => uint256) internal _bonusPoolLeaderboardPositionsCount;
    uint256 internal _bonusPoolLeaderboardFirst = 1;
    uint256 internal _bonusPoolLeaderboardLast = 0;
    uint256 constant internal BONUS_POOL_LEADERBOARD_MAX_USERS_COUNT = 10;
    uint256 constant internal BONUS_POOL_LEADERBOARD_MIN_STAKE_TO_QUALIFY = 1000;
    uint256 constant internal BONUS_POOL_LEADERBOARD_MIN_STAKE_TO_MAINTAIN_POSITION = 900; // 90%

// Bonus Timer settings
uint256 internal _bonusPoolTimer;
uint256 internal _bonusPoolLastDistributedAt=0;
uint256 constant internal BONUS_POOL_NEW_STAKEHOLDER_TIME_ADDITION = 900;   // 15 minutes
    uint256 constant internal BONUS_POOL_TIMER_INITIAL = 21600; // 6 hours

    // Platform Team wallets
    address[] internal _platformWallets;
    // Partner wallet
    address   internal _partnerWallet;

    event Staked(address indexed sender, uint256 amount, address indexed referrer);
    event Unstaked(address indexed sender, uint256 amount);
    event RewardWithdrawn(address indexed sender, uint256 amount);
    event BonusRewardPoolDistributed(uint256 amountAllUsers, uint256 amountLeaderboard);
    event MonthlyRewardPoolDistributed(uint256 amount);
    event Timer(uint256 timer);
    /// @param trustedToken_ A ERC20 trustedToken to use in this contract
    /// @param partnerWallet A Partner's wallet to reward
    /// @param platformWallets List of Platform Team's wallets
    constructor(
        address trustedToken_,
        address partnerWallet,
        address[] memory platformWallets
    ) Ownable() {  // solhint-disable func-visibility
        // solhint-disable mark-callable-contracts
        trustedToken = IERC20(trustedToken_);
        _platformWallets = platformWallets;
        _partnerWallet = partnerWallet;
        _bonusPoolTimer = BONUS_POOL_TIMER_INITIAL;
    }

    modifier AttemptToDistrubuteBonusPools() {
        if(_bonusPoolLastDistributedAt == 0 && _monthlyPoolLastDistributedAt== 0){
            // SWC-120-Weak Sources of Randomness from Chain Attributes: L96
            _bonusPoolLastDistributedAt = block.timestamp;
            // SWC-120-Weak Sources of Randomness from Chain Attributes: L98
            _monthlyPoolLastDistributedAt = block.timestamp;
        }
        _maybeDistributeMonthlyRewardPool();
        _maybeDistributeBonusRewardPool();
        _;
    }

    // External functions

    function stake(uint256 amount, address referrer) external AttemptToDistrubuteBonusPools {
        amount=amount*TOKEN_DECIMAL;
        require(amount != 0, "GreenHouse: staking zero");
        require(
            trustedToken.transferFrom(msg.sender, address(this), amount),
            "GreenHouse: staking transfer"
        );
        require(msg.sender!=referrer,"GreenHouse: You cannot indicate yourself as a referral ");
        if(_stakes[referrer]<100*TOKEN_DECIMAL){
            referrer=address(0);
        }
        if (!_hasStaked[msg.sender]) {
            _hasStaked[msg.sender] = true;
            everStakedUsersCount++;
        }
        if (amount >= BONUS_POOL_LEADERBOARD_MIN_STAKE_TO_QUALIFY*TOKEN_DECIMAL) {
            _bonusPoolProcessStakeholder(msg.sender);
        }

        _processStake(amount, referrer);
        emit Staked(msg.sender, amount, referrer);
    }

    function unstake(uint256 amount) external AttemptToDistrubuteBonusPools {
        amount=amount*TOKEN_DECIMAL;
        require(amount != 0, "GreenHouse: unstaking zero");
        require(_stakes[msg.sender] >= amount, "GreenHouse: unstake amount");

        (uint256 net, uint256 fee) = _applyFeesAndDistributeRewards(amount, address(0));
        _stakes[msg.sender] -= amount;
        _bonusPoolLeaderboardUnstakeToKick(msg.sender, _stakes[msg.sender]);

        // solhint-disable mark-callable-contracts
        _magnifiedRewardCorrections[msg.sender] += SafeCast.toInt256(_magnifiedRewardPerStake * amount);
        _rewardAllUsersStaked(fee);
        allStakes -= amount;

        require(
            trustedToken.transfer(msg.sender, net),
            "GreenHouse: unstake transfer"
        );

        emit Unstaked(msg.sender, amount);
    }

    function withdrawReward() external AttemptToDistrubuteBonusPools {
        uint256 withdrawable = withdrawableRewardOf(msg.sender);
        require(withdrawable > 0, "GreenHouse: nothing to withdraw");
        _withdrawals[msg.sender] += withdrawable;
        require(
            trustedToken.transfer(msg.sender, withdrawable),
            "GreenHouse: withdrawal transfer"
        );
        emit RewardWithdrawn(msg.sender, withdrawable);
    }

    function bonusPoolLeaderboard() external view returns(address[] memory) {
        uint256 leaderboardUsersCount = _bonusPoolLeaderboardUsersCount();
        address[] memory leaderboard = new address[](leaderboardUsersCount);
        uint256 ptr = 0;
        for (uint256 i = _bonusPoolLeaderboardFirst; i <= _bonusPoolLeaderboardLast; i++) {
            leaderboard[ptr] = _bonusPoolLeaderboard[i];
            ptr++;
        }
        return leaderboard;
    }
    // External functions only owner

    function setPartnerWallet(address address_) external onlyOwner {
        _partnerWallet = address_;
    }

    function setPlatformWallets(address[] memory addresses) external onlyOwner {
        _platformWallets = addresses;
    }


    // Public view functions

    function stakeOf(address stakeholder) public view returns(uint256) {
        return _stakes[stakeholder];
    }

    function accumulativeRewardOf(address stakeholder) public view returns(uint256) {
        // solhint-disable mark-callable-contracts
        return SafeCast.toUint256(
            SafeCast.toInt256(
                stakeOf(stakeholder) * _magnifiedRewardPerStake
            ) + _magnifiedRewardCorrections[stakeholder]
        ) / MAGNITUDE;
    }

    function withdrawnRewardOf(address stakeholder) public view returns(uint256) {
        return _withdrawals[stakeholder];
    }

    function withdrawableRewardOf(address stakeholder) public view returns(uint256) {
        return accumulativeRewardOf(stakeholder) - withdrawnRewardOf(stakeholder);
    }

    function bonusRewardPoolCountdown() public view returns(uint256) {
        // SWC-120-Weak Sources of Randomness from Chain Attributes: L209
        uint256 timeSinceLastDistributed = block.timestamp - _bonusPoolLastDistributedAt;
        if (timeSinceLastDistributed >= _bonusPoolTimer) return 0;
        return _bonusPoolTimer - timeSinceLastDistributed;
    }

    function monthlyRewardPoolCountdown() public view returns(uint256) {
        // SWC-120-Weak Sources of Randomness from Chain Attributes: L216
        uint256 timeSinceLastDistributed = block.timestamp - _monthlyPoolLastDistributedAt;
        if (timeSinceLastDistributed >= MONYHLY_POOL_TIMER) return 0;
        return MONYHLY_POOL_TIMER - timeSinceLastDistributed;
    }

    // internal functions

    function _bonusPoolLeaderboardPop() internal {
        address removed = _bonusPoolLeaderboard[_bonusPoolLeaderboardFirst];
        delete _bonusPoolLeaderboard[_bonusPoolLeaderboardFirst];
        _bonusPoolLeaderboardFirst++;
        _bonusPoolLeaderboardPositionsCount[removed]--;
        if (_bonusPoolLeaderboardPositionsCount[removed] == 0)
            delete _bonusPoolLeaderboardPositionsCount[removed];
    }

    function _bonusPoolLeaderboardPush(address value) internal {
        _bonusPoolLeaderboardLast++;
        _bonusPoolLeaderboard[_bonusPoolLeaderboardLast] = value;
        _bonusPoolLeaderboardPositionsCount[value] += 1;
        if((bonusRewardPoolCountdown()+BONUS_POOL_NEW_STAKEHOLDER_TIME_ADDITION) >= BONUS_POOL_TIMER_INITIAL){
            _bonusPoolTimer += 0;
        }else{
        _bonusPoolTimer += BONUS_POOL_NEW_STAKEHOLDER_TIME_ADDITION;
        }
        emit Timer(bonusRewardPoolCountdown()+BONUS_POOL_NEW_STAKEHOLDER_TIME_ADDITION);
    }

    /**
     @notice Adds new qualified staker to the Bonus Pool Leaderboard's queue
             and update Bonus Pool Timer
     @param stakeholder The address of a stakeholder
     */
    function _bonusPoolProcessStakeholder(address stakeholder) internal {
        _bonusPoolLeaderboardPush(stakeholder);

        if (_bonusPoolLeaderboardUsersCount() > BONUS_POOL_LEADERBOARD_MAX_USERS_COUNT)
            _bonusPoolLeaderboardPop();
    }

    function _bonusPoolLeaderboardKick(address stakeholder, uint256 positions) internal {
        // filter remaining participants
        uint256 positionsLeftToKick = positions;
        address[] memory leaderboard = new address[](_bonusPoolLeaderboardUsersCount() - positions);
        uint256 ptr = 0;
        for (
            uint256 i = _bonusPoolLeaderboardFirst;
            i <= _bonusPoolLeaderboardLast;
            i++
        ) {
            if (positionsLeftToKick > 0 && _bonusPoolLeaderboard[i] == stakeholder) {
                positionsLeftToKick--;
            } else {
                leaderboard[ptr] = _bonusPoolLeaderboard[i];
                ptr++;
            }

        }
        // rebuild the whole leaderboard :'(
        while (_bonusPoolLeaderboardUsersCount() > 0)
            _bonusPoolLeaderboardPop();
        for (uint256 i = 0; i < leaderboard.length; ++i)
            _bonusPoolLeaderboardPush(leaderboard[i]);
    }

    function _bonusPoolLeaderboardUnstakeToKick(address stakeholder, uint256 remaining) internal {
        uint256 maxPositions = remaining / BONUS_POOL_LEADERBOARD_MIN_STAKE_TO_MAINTAIN_POSITION;
        if (maxPositions < _bonusPoolLeaderboardPositionsCount[stakeholder]) {
            uint256 positionsToKick = _bonusPoolLeaderboardPositionsCount[stakeholder] - maxPositions;
            _bonusPoolLeaderboardKick(stakeholder, positionsToKick);
        }
    }

    function _bonusPoolLeaderboardUsersCount() internal view returns(uint256) {
        return _bonusPoolLeaderboardLast + 1 - _bonusPoolLeaderboardFirst;
    }

    function _transferRewardPartner(uint256 amount) internal {
        require(
            trustedToken.transfer(_partnerWallet, amount),
            "GreenHouse: partner transfer"
        );
    }

    function _transferRewardPlatform(uint256 amount) internal {
        uint256 perWallet = amount / _platformWallets.length;
        for (uint256 i = 0; i != _platformWallets.length; ++i) {
            require(
                trustedToken.transfer(_platformWallets[i], perWallet),
                "GreenHouse: platform transfer"
            );
        }
    }

    function _rewardAllUsersStaked(uint256 amount) internal {
        _magnifiedRewardPerStake += allStakes != 0 ? (MAGNITUDE * amount) / allStakes : 0;
    }

    function _transferRewardReferral(uint256 amount, address referrer) internal {
        referralRewards[referrer] += amount;
        bool success = trustedToken.transfer(referrer, amount);
        require(success, "GreenHouse: referral transfer");
    }

    function _rewardBonusPool(uint256 amount) internal {
        bonusRewardPool += amount;
    }

    function _rewardMonthlyPool(uint256 amount) internal {
        monthlyRewardPool += amount;
    }

    function _calculateFees(uint256 amount)
    internal pure
    returns(
        uint256 allUsers,
        uint256 bonusPool,
        uint256 partner,
        uint256 referral,
        uint256 platform,
        uint256 net
    ) {
        allUsers = (amount * FEE_ALL_USERS_STAKED_PERMILLE) / 10000;
        bonusPool = (amount * FEE_BONUS_POOL_PERMILLE) / 10000;
        partner = (amount * FEE_PARTNER_WALLET_PERMILLE) / 10000;
        referral = (amount * FEE_REFERRAL_PERMILLE) / 10000;
        platform = (amount * FEE_PLATFORM_WALLET_PERMILLE) / 10000;
        net = amount - allUsers - bonusPool - partner - referral - platform;
    }

    function _applyFeesAndDistributeRewards(uint256 amount, address referrer)
        internal
        returns(uint256, uint256)
    {
        (
            uint256 fee,
            uint256 feeBonusPool,
            uint256 feePartnerWallet,
            uint256 feeReferral,
            uint256 feePlatformWallet,
            uint256 net
        ) = _calculateFees(amount);

        _rewardBonusPool(feeBonusPool);
        _transferRewardPartner(feePartnerWallet);
        _transferRewardPlatform(feePlatformWallet);

        if (referrer == address(0))
            _rewardMonthlyPool(feeReferral);
        else
            _transferRewardReferral(feeReferral, referrer);

        return (net, fee);
    }
    function _processStake(uint256 amount, address referrer) internal {
        (uint256 net, uint256 fee) = _applyFeesAndDistributeRewards(amount, referrer);
        _stakes[msg.sender] += net;

        allStakes += net;
        // solhint-disable mark-callable-contracts
        _magnifiedRewardCorrections[msg.sender] -= SafeCast.toInt256(_magnifiedRewardPerStake * net);
        _rewardAllUsersStaked(fee);
    }

    function _maybeDistributeMonthlyRewardPool() internal {
        if (monthlyRewardPoolCountdown() == 0 && monthlyRewardPool != 0) {
            uint256 amountToDistribute = (monthlyRewardPool * MONTHLY_POOL_DISTRIBUTE_ALL_USERS_PERCENT) / 100;
            _rewardAllUsersStaked(amountToDistribute);
        // SWC-120-Weak Sources of Randomness from Chain Attributes: L386
            _monthlyPoolLastDistributedAt = block.timestamp;
            monthlyRewardPool -= amountToDistribute;
            emit MonthlyRewardPoolDistributed(amountToDistribute);
        }
    }

    function _maybeDistributeBonusRewardPool() internal {
        if (bonusRewardPoolCountdown() == 0 && bonusRewardPool != 0) {
            uint256 amountToDistributeAllUsers = (bonusRewardPool * BONUS_POOL_DISTRIBUTE_ALL_USERS_PERCENT) / 100;
            _rewardAllUsersStaked(amountToDistributeAllUsers);

            uint256 leaderboardUsersCount = _bonusPoolLeaderboardUsersCount();
            uint256 amountToDistributeLeaderboard = (bonusRewardPool * BONUS_POOL_DISTRIBUTE_LEADERBOARD_PERCENT) / 100;
            _bonusPoolTimer = BONUS_POOL_TIMER_INITIAL;  // reset bonus pool timer
        // SWC-120-Weak Sources of Randomness from Chain Attributes: L400
            _bonusPoolLastDistributedAt = block.timestamp;
            bonusRewardPool -= amountToDistributeAllUsers + amountToDistributeLeaderboard;

            if (leaderboardUsersCount != 0) {
                uint256 amountToDistributePerLeader = amountToDistributeLeaderboard / leaderboardUsersCount;

                if (amountToDistributePerLeader > 0)
                    for (uint256 i = _bonusPoolLeaderboardFirst; i <= _bonusPoolLeaderboardLast; ++i) {
                        require(
                            trustedToken.transfer(_bonusPoolLeaderboard[i], amountToDistributePerLeader),
                            "GreenHouse: bonus transfer"
                        );
                    }
            }

            emit BonusRewardPoolDistributed(amountToDistributeAllUsers, amountToDistributeLeaderboard);
        }
    }
}
