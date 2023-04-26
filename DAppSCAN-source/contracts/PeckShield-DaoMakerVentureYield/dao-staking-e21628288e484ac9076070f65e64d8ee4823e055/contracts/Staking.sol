//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./GlobalsAndUtility.sol";
import "./helpers/IERC20Burnable.sol";

contract Staking is GlobalsAndUtility {
    using SafeERC20 for IERC20Burnable;

    constructor(
        IERC20Burnable _stakingToken, // MUST BE BURNABLE
        uint40 _launchTime,
        address _originAddr
    )
    {
        require(IERC20Metadata(address(_stakingToken)).decimals() == TOKEN_DECIMALS, "STAKING: incompatible token decimals");
        require(_launchTime >= block.timestamp, "STAKING: launch must be in future");
        require(_originAddr != address(0), "STAKING: origin address is 0");

        stakingToken = _stakingToken;
        launchTime = _launchTime;
        originAddr = _originAddr;

        /* Initialize global shareRate to 1 */
        globals.shareRate = uint40(1 * SHARE_RATE_SCALE);
    }

    /**
     * @dev PUBLIC FACING: Open a stake.
     * @param newStakedAmount Amount of staking token to stake
     * @param newStakedDays Number of days to stake
     */
    function stakeStart(uint256 newStakedAmount, uint256 newStakedDays)
        external
    {
        GlobalsCache memory g;
        _globalsLoad(g);

        /* Enforce the minimum stake time */
        require(newStakedDays >= MIN_STAKE_DAYS, "STAKING: newStakedDays lower than minimum");
        /* Enforce the maximum stake time */
        require(newStakedDays <= MAX_STAKE_DAYS, "STAKING: newStakedDays higher than maximum");

        /* Check if log data needs to be updated */
        _dailyDataUpdateAuto(g);

        _stakeStart(g, newStakedAmount, newStakedDays);

        /* Remove staked amount from balance of staker */
        stakingToken.safeTransferFrom(msg.sender, address(this), newStakedAmount);

        _globalsSync(g);
    }

    /**
     * @dev PUBLIC FACING: Unlocks a completed stake, distributing the proceeds of any penalty
     * immediately. The staker must still call stakeEnd() to retrieve their stake return (if any).
     * @param stakerAddr Address of staker
     * @param stakeIndex Index of stake within stake list
     * @param stakeIdParam The stake's id
     */
    function stakeGoodAccounting(address stakerAddr, uint256 stakeIndex, uint40 stakeIdParam)
        external
    {
        GlobalsCache memory g;
        _globalsLoad(g);

        /* require() is more informative than the default assert() */
        require(stakeLists[stakerAddr].length != 0, "STAKING: Empty stake list");
        require(stakeIndex < stakeLists[stakerAddr].length, "STAKING: stakeIndex invalid");

        StakeStore storage stRef = stakeLists[stakerAddr][stakeIndex];

        /* Get stake copy */
        StakeCache memory st;
        _stakeLoad(stRef, stakeIdParam, st);

        /* Stake must have served full term */
        require(g._currentDay >= st._lockedDay + st._stakedDays, "STAKING: Stake not fully served");

        /* Stake must still be locked */
        require(st._unlockedDay == 0, "STAKING: Stake already unlocked");

        /* Check if log data needs to be updated */
        _dailyDataUpdateAuto(g);

        /* Unlock the completed stake */
        _stakeUnlock(g, st);

        /* stakeReturn value is unused here */
        (, uint256 payout, uint256 penalty, uint256 cappedPenalty) = _stakePerformance(
            st,
            st._stakedDays
        );

        emit StakeGoodAccounting(
            stakerAddr,
            stakeIdParam,
            msg.sender,
            uint40(block.timestamp),
            uint128(st._stakedAmount),
            uint128(st._stakeShares),
            uint128(payout),
            uint128(penalty)
        );

        if (cappedPenalty != 0) {
            _splitPenaltyProceeds(g, cappedPenalty);
        }

        /* st._unlockedDay has changed */
        _stakeUpdate(stRef, st);

        _globalsSync(g);
    }

    /**
     * @dev PUBLIC FACING: Closes a stake. The order of the stake list can change so
     * a stake id is used to reject stale indexes.
     * @param stakeIndex Index of stake within stake list
     * @param stakeIdParam The stake's id
     * @return stakeReturn payout penalty
     */
    function stakeEnd(uint256 stakeIndex, uint40 stakeIdParam)
        external
        returns (uint256 stakeReturn, uint256 payout, uint256 penalty, uint256 cappedPenalty)
    {
        GlobalsCache memory g;
        _globalsLoad(g);

        StakeStore[] storage stakeListRef = stakeLists[msg.sender];

        /* require() is more informative than the default assert() */
        require(stakeListRef.length != 0, "STAKING: Empty stake list");
        require(stakeIndex < stakeListRef.length, "STAKING: stakeIndex invalid");

        /* Get stake copy */
        StakeCache memory st;
        _stakeLoad(stakeListRef[stakeIndex], stakeIdParam, st);

        /* Check if log data needs to be updated */
        _dailyDataUpdateAuto(g);

        require(g._currentDay >= st._lockedDay + HARD_LOCK_DAYS, "STAKING: hard lock period");

        uint256 servedDays = 0;
        bool prevUnlocked = (st._unlockedDay != 0);

        if (prevUnlocked) {
            /* Previously unlocked in stakeGoodAccounting(), so must have served full term */
            servedDays = st._stakedDays;
        } else {
            _stakeUnlock(g, st);

            servedDays = g._currentDay - st._lockedDay;
            if (servedDays > st._stakedDays) {
                servedDays = st._stakedDays;
            }
        }

        (stakeReturn, payout, penalty, cappedPenalty) = _stakePerformance(st, servedDays);

        emit StakeEnd(
            msg.sender,
            stakeIdParam,
            uint40(block.timestamp),
            uint128(st._stakedAmount),
            uint128(st._stakeShares),
            uint128(payout),
            uint128(penalty),
            uint16(servedDays),
            prevUnlocked
        );

        if (cappedPenalty != 0 && !prevUnlocked) {
            /* Split penalty proceeds only if not previously unlocked by stakeGoodAccounting() */
            _splitPenaltyProceeds(g, cappedPenalty);
        }

        /* Pay the stake return, if any, to the staker */
        if (stakeReturn != 0) {
            stakingToken.safeTransfer(msg.sender, stakeReturn);

            /* Update the share rate if necessary */
            _shareRateUpdate(g, st, stakeReturn);
        }
        g._lockedStakeTotal -= st._stakedAmount;

        _stakeRemove(stakeListRef, stakeIndex);

        _globalsSync(g);

        return (
            stakeReturn,
            payout,
            penalty,
            cappedPenalty
        );
    }
 
    function fundRewards(
        uint128 amountPerDay,
        uint16 daysCount,
        uint16 shiftInDays
    )
        external
    {
        require(daysCount <= 365, "STAKING: too many days");

        stakingToken.safeTransferFrom(msg.sender, address(this), amountPerDay * daysCount);

        uint256 currentDay = _currentDay() + 1;
        uint256 fromDay = currentDay + shiftInDays;

        for (uint256 day = fromDay; day < fromDay + daysCount; day++) {
            dailyData[day].dayPayoutTotal += amountPerDay;
        }

        emit RewardsFund(amountPerDay, daysCount, shiftInDays);
    }

    /**
     * @dev PUBLIC FACING: Return the current stake count for a staker address
     * @param stakerAddr Address of staker
     */
    function stakeCount(address stakerAddr)
        external
        view
        returns (uint256)
    {
        return stakeLists[stakerAddr].length;
    }

    /**
     * @dev Open a stake.
     * @param g Cache of stored globals
     * @param newStakedAmount Amount of staking token to stake
     * @param newStakedDays Number of days to stake
     */
    function _stakeStart(
        GlobalsCache memory g,
        uint256 newStakedAmount,
        uint256 newStakedDays
    )
        internal
    {
        uint256 bonusShares = stakeStartBonusShares(newStakedAmount, newStakedDays);
        uint256 newStakeShares = (newStakedAmount + bonusShares) * SHARE_RATE_SCALE / g._shareRate;

        /* Ensure newStakedAmount is enough for at least one stake share */
        require(newStakeShares != 0, "STAKING: newStakedAmount must be at least minimum shareRate");

        /*
            The stakeStart timestamp will always be part-way through the current
            day, so it needs to be rounded-up to the next day to ensure all
            stakes align with the same fixed calendar days. The current day is
            already rounded-down, so rounded-up is current day + 1.
        */
        uint256 newLockedDay = g._currentDay + 1;

        /* Create Stake */
        uint40 newStakeId = ++g._latestStakeId;
        _stakeAdd(
            stakeLists[msg.sender],
            newStakeId,
            newStakedAmount,
            newStakeShares,
            newLockedDay,
            newStakedDays
        );

        emit StakeStart(
            msg.sender,
            newStakeId,
            uint40(block.timestamp),
            uint128(newStakedAmount),
            uint128(newStakeShares),
            uint16(newStakedDays)
        );

        /* Stake is added to total in the next round, not the current round */
        g._nextStakeSharesTotal += newStakeShares;

        /* Track total staked amount for inflation calculations */
        g._lockedStakeTotal += newStakedAmount;

        /* Remove his share from the pool when his stake ends */
        dailyData[newLockedDay + newStakedDays].sharesToBeRemoved += uint128(newStakeShares);
    }

    /* 
    Returns the same values as function stakeEnd. However, this function makes 
    it possible to anyone view the stakeReturn etc. for any staker. 

    The results can be obsolete if there are no daily updates.
    */
    function getStakeStatus(
        address staker, 
        uint256 stakeIndex, 
        uint40 stakeIdParam
    ) 
        external
        view
        returns (uint256 stakeReturn, uint256 payout, uint256 penalty, uint256 cappedPenalty)
    {
        GlobalsCache memory g;
        _globalsLoad(g);

        StakeStore[] storage stakeListRef = stakeLists[staker];

        require(stakeListRef.length != 0, "STAKING: Empty stake list");
        require(stakeIndex < stakeListRef.length, "STAKING: stakeIndex invalid");

        StakeCache memory st;
        _stakeLoad(stakeListRef[stakeIndex], stakeIdParam, st);

        require(g._currentDay >= st._lockedDay + HARD_LOCK_DAYS, "STAKING: hard lock period");

        uint256 servedDays = 0;
        bool prevUnlocked = (st._unlockedDay != 0);

        if (prevUnlocked) {
            servedDays = st._stakedDays;
        } else {
            st._unlockedDay = g._currentDay;

            servedDays = g._currentDay - st._lockedDay;
            if (servedDays > st._stakedDays) {
                servedDays = st._stakedDays;
            }
        }

        (stakeReturn, payout, penalty, cappedPenalty) = _stakePerformance(st, servedDays);
    }

    /**
     * @dev Calculates total stake payout including rewards for a multi-day range
     * @param stakeSharesParam Param from stake to calculate bonuses for
     * @param beginDay First day to calculate bonuses for
     * @param endDay Last day (non-inclusive) of range to calculate bonuses for
     * @return payout
     */
    function _calcPayoutRewards(
        uint256 stakeSharesParam,
        uint256 beginDay,
        uint256 endDay
    )
        private
        view
        returns (uint256 payout)
    {
        uint256 accRewardPerShare = dailyData[endDay - 1].accRewardPerShare - dailyData[beginDay - 1].accRewardPerShare;
        payout = stakeSharesParam * accRewardPerShare / ACC_REWARD_MULTIPLIER;
        return payout;
    }

    /**
     * @dev Calculate bonus shares for a new stake, if any
     * @param newStakedAmount Amount of staking token
     * @param newStakedDays Number of days to stake
     */
    function stakeStartBonusShares(uint256 newStakedAmount, uint256 newStakedDays)
        public
        pure
        returns (uint256 bonusShares)
    {
        /*
            LONGER PAYS BETTER:

            If longer than 1 day stake is committed to, each extra day
            gives bonus shares of approximately 0.0548%, which is approximately 20%
            extra per year of increased stake length committed to, but capped to a
            maximum of 200% extra.

            extraDays       =  stakedDays - 1

            longerBonus%    = (extraDays / 364) * 20%
                            = (extraDays / 364) / 5
                            =  extraDays / 1820
                            =  extraDays / LPB

            extraDays       =  longerBonus% * 1820
            extraDaysMax    =  longerBonusMax% * 1820
                            =  200% * 1820
                            =  3640
                            =  LPB_MAX_DAYS

            BIGGER PAYS BETTER:

            Bonus percentage scaled 0% to 10% for the first 150M of stake.

            biggerBonus%    = (cappedStake /  BPB_MAX) * 10%
                            = (cappedStake /  BPB_MAX) / 10
                            =  cappedStake / (BPB_MAX * 10)
                            =  cappedStake /  BPB

            COMBINED:

            combinedBonus%  =            longerBonus%  +  biggerBonus%

                                      cappedExtraDays     cappedStake
                            =         ---------------  +  ------------
                                            LPB               BPB

                                cappedExtraDays * BPB     cappedStake * LPB
                            =   ---------------------  +  ------------------
                                      LPB * BPB               LPB * BPB

                                cappedExtraDays * BPB  +  cappedStake * LPB
                            =   --------------------------------------------
                                                  LPB  *  BPB

            bonusShares     = stake * combinedBonus%
                            = stake * (cappedExtraDays * BPB  +  cappedStake * LPB) / (LPB * BPB)
        */
        uint256 cappedExtraDays = 0;

        /* Must be more than 1 day for Longer-Pays-Better */
        if (newStakedDays > 1) {
            cappedExtraDays = newStakedDays <= LPB_MAX_DAYS ? newStakedDays - 1 : LPB_MAX_DAYS;
        }

        uint256 cappedStakedAmount = newStakedAmount >= BPB_FROM_AMOUNT ? newStakedAmount - BPB_FROM_AMOUNT : 0;
        if (cappedStakedAmount > BPB_MAX) {
            cappedStakedAmount = BPB_MAX;
        }

        bonusShares = cappedExtraDays * BPB + cappedStakedAmount * LPB;
        bonusShares = newStakedAmount * bonusShares / (LPB * BPB);

        return bonusShares;
    }

    function _stakeUnlock(GlobalsCache memory g, StakeCache memory st)
        private
    {
        st._unlockedDay = g._currentDay;

        uint256 endDay = st._lockedDay + st._stakedDays;
        
        if (g._currentDay <= endDay) {
            dailyData[endDay].sharesToBeRemoved -= uint128(st._stakeShares);
            g._stakeSharesTotal -= st._stakeShares;
        }
    }

    function _stakePerformance(StakeCache memory st, uint256 servedDays)
        private
        view
        returns (uint256 stakeReturn, uint256 payout, uint256 penalty, uint256 cappedPenalty)
    {
        if (servedDays < st._stakedDays) {
            (payout, penalty) = _calcPayoutAndEarlyPenalty(
                st._lockedDay,
                st._stakedDays,
                servedDays,
                st._stakeShares
            );
            stakeReturn = st._stakedAmount + payout;
        } else {
            // servedDays must == stakedDays here
            payout = _calcPayoutRewards(
                st._stakeShares,
                st._lockedDay,
                st._lockedDay + servedDays
            );
            stakeReturn = st._stakedAmount + payout;

            penalty = _calcLatePenalty(st._lockedDay, st._stakedDays, st._unlockedDay, stakeReturn);
        }
        if (penalty != 0) {
            if (penalty > stakeReturn) {
                /* Cannot have a negative stake return */
                cappedPenalty = stakeReturn;
                stakeReturn = 0;
            } else {
                /* Remove penalty from the stake return */
                cappedPenalty = penalty;
                stakeReturn -= cappedPenalty;
            }
        }
        return (stakeReturn, payout, penalty, cappedPenalty);
    }

    function _calcPayoutAndEarlyPenalty(
        uint256 lockedDayParam,
        uint256 stakedDaysParam,
        uint256 servedDays,
        uint256 stakeSharesParam
    )
        private
        view
        returns (uint256 payout, uint256 penalty)
    {
        uint256 servedEndDay = lockedDayParam + servedDays;

        /* 50% of stakedDays (rounded up) with a minimum applied */
        uint256 penaltyDays = (stakedDaysParam + 1) / 2;
        if (penaltyDays < EARLY_PENALTY_MIN_DAYS) {
            penaltyDays = EARLY_PENALTY_MIN_DAYS;
        }

        if (penaltyDays < servedDays) {
            /*
                Simplified explanation of intervals where end-day is non-inclusive:

                penalty:    [lockedDay  ...  penaltyEndDay)
                delta:                      [penaltyEndDay  ...  servedEndDay)
                payout:     [lockedDay  .......................  servedEndDay)
            */
            uint256 penaltyEndDay = lockedDayParam + penaltyDays;
            penalty = _calcPayoutRewards(stakeSharesParam, lockedDayParam, penaltyEndDay);

            uint256 delta = _calcPayoutRewards(stakeSharesParam, penaltyEndDay, servedEndDay);
            payout = penalty + delta;
            return (payout, penalty);
        }

        /* penaltyDays >= servedDays  */
        payout = _calcPayoutRewards(stakeSharesParam, lockedDayParam, servedEndDay);

        if (penaltyDays == servedDays) {
            penalty = payout;
        } else {
            /*
                (penaltyDays > servedDays) means not enough days served, so fill the
                penalty days with the average payout from only the days that were served.
            */
            penalty = payout * penaltyDays / servedDays;
        }
        return (payout, penalty);
    }

    function _calcLatePenalty(
        uint256 lockedDayParam,
        uint256 stakedDaysParam,
        uint256 unlockedDayParam,
        uint256 rawStakeReturn
    )
        private
        pure
        returns (uint256)
    {
        /* Allow grace time before penalties accrue */
        uint256 maxUnlockedDay = lockedDayParam + stakedDaysParam + LATE_PENALTY_GRACE_DAYS;
        if (unlockedDayParam <= maxUnlockedDay) {
            return 0;
        }

        /* Calculate penalty as a percentage of stake return based on time */
        return rawStakeReturn * (unlockedDayParam - maxUnlockedDay) / LATE_PENALTY_SCALE_DAYS;
    }

    function _splitPenaltyProceeds(GlobalsCache memory g, uint256 penalty)
        private
    {
        /* Split a penalty 50:50 between (Origin + burn) and stakePenaltyTotal */
        uint256 splitPenalty = penalty / 2;

        if (splitPenalty != 0) {
            //30% of the total penalty is sent to origin address
            uint256 originPenalty = splitPenalty * 3 / 5;
            stakingToken.safeTransfer(originAddr, originPenalty);

            //20% of the total penalty is burned
            stakingToken.burn(splitPenalty - originPenalty);
        }

        /* Use the other half of the penalty to account for an odd-numbered penalty */
        splitPenalty = penalty - splitPenalty;
        g._stakePenaltyTotal += splitPenalty;
    }

    function _shareRateUpdate(GlobalsCache memory g, StakeCache memory st, uint256 stakeReturn)
        private
    {
        if (stakeReturn > st._stakedAmount) {
            /*
                Calculate the new shareRate that would yield the same number of shares if
                the user re-staked this stakeReturn, factoring in any bonuses they would
                receive in stakeStart().
            */
            uint256 bonusShares = stakeStartBonusShares(stakeReturn, st._stakedDays);
            uint256 newShareRate = (stakeReturn + bonusShares) * SHARE_RATE_SCALE / st._stakeShares;

            if (newShareRate > SHARE_RATE_MAX) {
                /*
                    Realistically this can't happen, but there are contrived theoretical
                    scenarios that can lead to extreme values of newShareRate, so it is
                    capped to prevent them anyway.
                */
                newShareRate = SHARE_RATE_MAX;
            }

            if (newShareRate > g._shareRate) {
                g._shareRate = newShareRate;

                emit ShareRateChange(
                    st._stakeId,
                    uint40(block.timestamp),
                    uint40(newShareRate)
                );
            }
        }
    }
}
