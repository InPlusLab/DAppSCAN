//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/IERC20Burnable.sol";

abstract contract GlobalsAndUtility {
    event DailyDataUpdate(
        address indexed updaterAddr,
        uint40 timestamp,
        uint16 beginDay,
        uint16 endDay,
        bool isAutoUpdate
    );

    event StakeStart(
        address indexed stakerAddr,
        uint40 indexed stakeId,
        uint40 timestamp,
        uint128 stakedAmount,
        uint128 stakeShares,
        uint16 stakedDays
    );

    event StakeGoodAccounting(        
        address indexed stakerAddr,
        uint40 indexed stakeId,
        address indexed senderAddr,
        uint40 timestamp,
        uint128 stakedAmount,
        uint128 stakeShares,
        uint128 payout,
        uint128 penalty
    );

    event StakeEnd(
        address indexed stakerAddr,
        uint40 indexed stakeId,
        uint40 timestamp,
        uint128 stakedAmount,
        uint128 stakeShares,
        uint128 payout,
        uint128 penalty,
        uint16 servedDays,
        bool prevUnlocked
    );

    event ShareRateChange(
        uint40 indexed stakeId,
        uint40 timestamp,
        uint40 shareRate
    );

    event RewardsFund(
        uint128 amountPerDay,
        uint16 daysCount,
        uint16 shiftInDays
    );

    IERC20Burnable public stakingToken;
    uint40 public launchTime;
    address public originAddr;

    uint256 internal constant ACC_REWARD_MULTIPLIER = 1e36;
    uint256 internal constant TOKEN_DECIMALS = 18;

    /* Stake timing parameters */
    uint256 internal constant HARD_LOCK_DAYS = 15;
    uint256 internal constant MIN_STAKE_DAYS = 30;
    uint256 internal constant MAX_STAKE_DAYS = 1095;
    uint256 internal constant EARLY_PENALTY_MIN_DAYS = 30;
    uint256 internal constant LATE_PENALTY_GRACE_DAYS = 30;
    uint256 internal constant LATE_PENALTY_SCALE_DAYS = 100;

    /* Stake shares Longer Pays Better bonus constants used by _stakeStartBonusShares() */
    uint256 private constant LPB_BONUS_PERCENT = 600;
    uint256 private constant LPB_BONUS_MAX_PERCENT = 1800;
    uint256 internal constant LPB = 364 * 100 / LPB_BONUS_PERCENT;
    uint256 internal constant LPB_MAX_DAYS = LPB * LPB_BONUS_MAX_PERCENT / 100;

    /* Stake shares Bigger Pays Better bonus constants used by _stakeStartBonusShares() */
    uint256 private constant BPB_BONUS_PERCENT = 50;
    uint256 internal constant BPB_MAX = 1e6 * 10 ** TOKEN_DECIMALS;
    uint256 internal constant BPB = BPB_MAX * 100 / BPB_BONUS_PERCENT;
    uint256 internal constant BPB_FROM_AMOUNT = 50000 * 10 ** TOKEN_DECIMALS;

    /* Share rate is scaled to increase precision */
    uint256 internal constant SHARE_RATE_SCALE = 1e5;

    /* Share rate max (after scaling) */
    uint256 internal constant SHARE_RATE_UINT_SIZE = 40;
    uint256 internal constant SHARE_RATE_MAX = (1 << SHARE_RATE_UINT_SIZE) - 1;

    /* Globals expanded for memory (except _latestStakeId) and compact for storage */
    struct GlobalsCache {
        uint256 _lockedStakeTotal;
        uint256 _nextStakeSharesTotal;

        uint256 _stakePenaltyTotal;
        uint256 _stakeSharesTotal;

        uint40 _latestStakeId;
        uint256 _shareRate;
        uint256 _dailyDataCount;

        uint256 _currentDay;
    }

    struct GlobalsStore {
        uint128 lockedStakeTotal;
        uint128 nextStakeSharesTotal;

        uint128 stakePenaltyTotal;
        uint128 stakeSharesTotal;

        uint40 latestStakeId;
        uint40 shareRate;
        uint16 dailyDataCount;
    }

    GlobalsStore public globals;

    /* Daily data */
    struct DailyDataStore {
        uint128 dayPayoutTotal;
        uint128 sharesToBeRemoved;
        uint256 accRewardPerShare;
    }

    mapping(uint256 => DailyDataStore) public dailyData;

    /* Stake expanded for memory (except _stakeId) and compact for storage */
    struct StakeCache {
        uint256 _stakedAmount;
        uint256 _stakeShares;
        uint40 _stakeId;
        uint256 _lockedDay;
        uint256 _stakedDays;
        uint256 _unlockedDay;
    }

    struct StakeStore {
        uint128 stakedAmount;
        uint128 stakeShares;
        uint40 stakeId;
        uint16 lockedDay;
        uint16 stakedDays;
        uint16 unlockedDay;
    }

    mapping(address => StakeStore[]) public stakeLists;

    /* Temporary state for calculating daily rounds */
    struct DailyRoundState {
        uint256 _payoutTotal;
        uint256 _accRewardPerShare;
    }

    /**
     * @dev PUBLIC FACING: Optionally update daily data for a smaller
     * range to reduce gas cost for a subsequent operation
     * @param beforeDay Only update days before this day number (optional; 0 for current day)
     */
    function dailyDataUpdate(uint256 beforeDay)
        external
    {
        GlobalsCache memory g;
        _globalsLoad(g);

        if (beforeDay != 0) {
            require(beforeDay <= g._currentDay, "STAKING: beforeDay cannot be in the future");

            _dailyDataUpdate(g, beforeDay, false);
        } else {
            /* Default to updating before current day */
            _dailyDataUpdate(g, g._currentDay, false);
        }

        _globalsSync(g);
    }

    /**
     * @dev PUBLIC FACING: External helper to return multiple values of daily data with
     * a single call. Ugly implementation due to limitations of the standard ABI encoder.
     * @param beginDay First day of data range
     * @param endDay Last day (non-inclusive) of data range
     * @return listDayAccRewardPerShare and listDayPayoutTotal
     */
    function dailyDataRange(uint256 beginDay, uint256 endDay)
        external
        view
        returns (uint256[] memory listDayAccRewardPerShare, uint256[] memory listDayPayoutTotal)
    {
        require(beginDay < endDay, "STAKING: range invalid");

        listDayAccRewardPerShare = new uint256[](endDay - beginDay);
        listDayPayoutTotal = new uint256[](endDay - beginDay);

        uint256 src = beginDay;
        uint256 dst = 0;
        do {
            listDayAccRewardPerShare[dst] = dailyData[src].accRewardPerShare;
            listDayPayoutTotal[dst++] = dailyData[src].dayPayoutTotal;
        } while (++src < endDay);
    }

    /**
     * @dev PUBLIC FACING: External helper to return most global info with a single call.
     * @return global variables
     */
    function globalInfo()
        external
        view
        returns (GlobalsCache memory)
    {
        GlobalsCache memory g;
        _globalsLoad(g);

        return g;
    }

    /**
     * @dev PUBLIC FACING: External helper for the current day number since launch time
     * @return Current day number (zero-based)
     */
    function currentDay()
        external
        view
        returns (uint256)
    {
        return _currentDay();
    }

    function _currentDay()
        internal
        view
        returns (uint256)
    {
        return (block.timestamp - launchTime) / 1 days;
    }

    function _dailyDataUpdateAuto(GlobalsCache memory g)
        internal
    {
        _dailyDataUpdate(g, g._currentDay, true);
    }

    function _globalsLoad(GlobalsCache memory g)
        internal
        view
    {
        g._lockedStakeTotal = globals.lockedStakeTotal;
        g._nextStakeSharesTotal = globals.nextStakeSharesTotal;

        g._stakeSharesTotal = globals.stakeSharesTotal;
        g._stakePenaltyTotal = globals.stakePenaltyTotal;

        g._latestStakeId = globals.latestStakeId;
        g._shareRate = globals.shareRate;
        g._dailyDataCount = globals.dailyDataCount;
        
        g._currentDay = _currentDay();
    }

    function _globalsSync(GlobalsCache memory g)
        internal
    {
        globals.lockedStakeTotal = uint128(g._lockedStakeTotal);
        globals.nextStakeSharesTotal = uint128(g._nextStakeSharesTotal);

        globals.stakeSharesTotal = uint128(g._stakeSharesTotal);
        globals.stakePenaltyTotal = uint128(g._stakePenaltyTotal);

        globals.latestStakeId = g._latestStakeId;
        globals.shareRate = uint40(g._shareRate);
        globals.dailyDataCount = uint16(g._dailyDataCount);
    }

    function _stakeLoad(StakeStore storage stRef, uint40 stakeIdParam, StakeCache memory st)
        internal
        view
    {
        /* Ensure caller's stakeIndex is still current */
        require(stakeIdParam == stRef.stakeId, "STAKING: stakeIdParam not in stake");

        st._stakedAmount = stRef.stakedAmount;
        st._stakeShares = stRef.stakeShares;
        st._stakeId = stRef.stakeId;
        st._lockedDay = stRef.lockedDay;
        st._stakedDays = stRef.stakedDays;
        st._unlockedDay = stRef.unlockedDay;
    }

    function _stakeUpdate(StakeStore storage stRef, StakeCache memory st)
        internal
    {
        stRef.stakedAmount = uint128(st._stakedAmount);
        stRef.stakeShares = uint128(st._stakeShares);
        stRef.stakeId = st._stakeId;
        stRef.lockedDay = uint16(st._lockedDay);
        stRef.stakedDays = uint16(st._stakedDays);
        stRef.unlockedDay = uint16(st._unlockedDay);
    }

    function _stakeAdd(
        StakeStore[] storage stakeListRef,
        uint40 newStakeId,
        uint256 newstakedAmount,
        uint256 newStakeShares,
        uint256 newLockedDay,
        uint256 newStakedDays
    )
        internal
    {
        stakeListRef.push(
            StakeStore(
                uint128(newstakedAmount),
                uint128(newStakeShares),
                newStakeId,
                uint16(newLockedDay),
                uint16(newStakedDays),
                uint16(0) // unlockedDay
            )
        );
    }

    /**
     * @dev Efficiently delete from an unordered array by moving the last element
     * to the "hole" and reducing the array length. Can change the order of the list
     * and invalidate previously held indexes.
     * @notice stakeListRef length and stakeIndex are already ensured valid in stakeEnd()
     * @param stakeListRef Reference to stakeLists[stakerAddr] array in storage
     * @param stakeIndex Index of the element to delete
     */
    function _stakeRemove(StakeStore[] storage stakeListRef, uint256 stakeIndex)
        internal
    {
        uint256 lastIndex = stakeListRef.length - 1;

        /* Skip the copy if element to be removed is already the last element */
        if (stakeIndex != lastIndex) {
            /* Copy last element to the requested element's "hole" */
            stakeListRef[stakeIndex] = stakeListRef[lastIndex];
        }

        stakeListRef.pop();
    }

    function _dailyRoundCalc(GlobalsCache memory g, DailyRoundState memory rs, uint256 day)
        private
        view
    {
        rs._payoutTotal = dailyData[day].dayPayoutTotal;
        rs._accRewardPerShare = day == 0 ? 0 : dailyData[day - 1].accRewardPerShare;

        if (g._stakePenaltyTotal != 0) {
            rs._payoutTotal += g._stakePenaltyTotal;
            g._stakePenaltyTotal = 0;
        }

        if (g._stakeSharesTotal > 0) {
            rs._accRewardPerShare += rs._payoutTotal * ACC_REWARD_MULTIPLIER / g._stakeSharesTotal;
        }
    }

    function _dailyRoundCalcAndStore(GlobalsCache memory g, DailyRoundState memory rs, uint256 day)
        private
    {
        g._stakeSharesTotal -= dailyData[day].sharesToBeRemoved;

        _dailyRoundCalc(g, rs, day);

        dailyData[day].accRewardPerShare = rs._accRewardPerShare;

        if (g._stakeSharesTotal > 0) {
            dailyData[day].dayPayoutTotal = uint128(rs._payoutTotal);
        } else {
            // nobody staking that day, move the reward to the next day if any
            dailyData[day + 1].dayPayoutTotal += uint128(rs._payoutTotal);
        }
    }

    function _dailyDataUpdate(GlobalsCache memory g, uint256 beforeDay, bool isAutoUpdate)
        private
    {
        if (g._dailyDataCount >= beforeDay) {
            /* Already up-to-date */
            return;
        }

        DailyRoundState memory rs;

        uint256 day = g._dailyDataCount;

        _dailyRoundCalcAndStore(g, rs, day);

        /* Stakes started during this day are added to the total the next day */
        if (g._nextStakeSharesTotal != 0) {
            g._stakeSharesTotal += g._nextStakeSharesTotal;
            g._nextStakeSharesTotal = 0;
        }

        while (++day < beforeDay) {
            _dailyRoundCalcAndStore(g, rs, day);
        }

        emit DailyDataUpdate(
            msg.sender,
            uint40(block.timestamp),
            uint16(g._dailyDataCount),
            uint16(day),
            isAutoUpdate
        );

        g._dailyDataCount = day;
    }
}