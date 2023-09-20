// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

import "./BaseFlywheelRewards.sol";

import {ERC20Gauges} from "../token/ERC20Gauges.sol";

/// @notice a contract which streams reward tokens to the FlywheelRewards module
interface IRewardsStream {
    /// @notice read and transfer reward token chunk to FlywheelRewards module
    function getRewards() external returns (uint256);
}

/** 
 @title Flywheel Gauge Reward Stream
 @notice Distributes rewards from a stream based on gauge weights

 The contract assumes an arbitrary stream of rewards `S` of rewardToken. It chunks the rewards into cycles of length `l`.

 The allocation function for each cycle A(g, S) proportions the stream to each gauge such that SUM(A(g, S)) over all gauges <= S. 
 NOTE it should be approximately S, but may be less due to truncation.

 Rewards are accumulated every time a new rewards cycle begins, and all prior rewards are cached in the previous cycle.
 When the Flywheel Core requests accrued rewards for a specific gauge:
 1. All prior rewards before this cycle are distributed
 2. Rewards for the current cycle are distributed proportionally to the remaining time in the cycle. 
    If `e` is the cycle end, `t` is the min of e and current timestamp, and `p` is the prior updated time:
    For `A` accrued rewards over the cycle, distribute `min(A * (t-p)/(e-p), A)`.
*/
contract FlywheelGaugeRewards is Auth, BaseFlywheelRewards {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    /// @notice thrown when trying to queue a new cycle during an old one.
    error CycleError();

    /// @notice thrown when trying to queue with 0 gauges
    error EmptyGaugesError();

    /// @notice emitted when a cycle has completely queued and started
    event CycleStart(uint32 indexed cycleStart, uint256 rewardAmount);

    /// @notice emitted when a single gauge is queued. May be emitted before the cycle starts if the queue is done via pagination.
    event QueueRewards(address indexed gauge, uint32 indexed cycleStart, uint256 rewardAmount);

    /// @notice the start of the current cycle
    uint32 public gaugeCycle;

    /// @notice the length of a rewards cycle
    uint32 public immutable gaugeCycleLength;

    /// @notice the start of the next cycle being partially queued
    uint32 internal nextCycle;

    // rewards that made it into a partial queue but didn't get completed
    uint112 internal nextCycleQueuedRewards;

    // the offset during pagination of the queue
    uint32 internal paginationOffset;

    /// @notice rewards queued from prior and current cycles
    struct QueuedRewards {
        uint112 priorCycleRewards;
        uint112 cycleRewards;
        uint32 storedCycle;
    }

    /// @notice mapping from gauges to queued rewards
    mapping(ERC20 => QueuedRewards) public gaugeQueuedRewards;

    /// @notice the gauge token for determining gauge allocations of the rewards stream
    ERC20Gauges public immutable gaugeToken;

    /// @notice contract to pull reward tokens from
    IRewardsStream public rewardsStream;

    constructor(
        FlywheelCore _flywheel,
        address _owner,
        Authority _authority,
        ERC20Gauges _gaugeToken,
        IRewardsStream _rewardsStream
    ) BaseFlywheelRewards(_flywheel) Auth(_owner, _authority) {
        gaugeCycleLength = _gaugeToken.gaugeCycleLength();

        // seed initial gaugeCycle
        gaugeCycle = (block.timestamp.safeCastTo32() / gaugeCycleLength) * gaugeCycleLength;

        gaugeToken = _gaugeToken;

        rewardsStream = _rewardsStream;
    }

    /**
        @notice Iterates over all live gauges and queues up the rewards for the cycle
        @return totalQueuedForCycle the max amount of rewards to be distributed over the cycle
    */
    function queueRewardsForCycle() external requiresAuth returns (uint256 totalQueuedForCycle) {
        // next cycle is always the next even divisor of the cycle length above current block timestamp.
        uint32 currentCycle = (block.timestamp.safeCastTo32() / gaugeCycleLength) * gaugeCycleLength;
        uint32 lastCycle = gaugeCycle;

        // ensure new cycle has begun
        if (currentCycle <= lastCycle) revert CycleError();

        gaugeCycle = currentCycle;

        // queue the rewards stream and sanity check the tokens were received
        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        totalQueuedForCycle = rewardsStream.getRewards();
        require(rewardToken.balanceOf(address(this)) - balanceBefore >= totalQueuedForCycle);

        // include uncompleted cycle
        totalQueuedForCycle += nextCycleQueuedRewards;

        // iterate over all gauges and update the rewards allocations
        address[] memory gauges = gaugeToken.gauges();

        _queueRewards(gauges, currentCycle, lastCycle, totalQueuedForCycle);

        nextCycleQueuedRewards = 0;
        paginationOffset = 0;

        emit CycleStart(currentCycle, totalQueuedForCycle);
    }

    /**
        @notice Iterates over all live gauges and queues up the rewards for the cycle
    */
    function queueRewardsForCyclePaginated(uint256 numRewards) external requiresAuth {
        // next cycle is always the next even divisor of the cycle length above current block timestamp.
        uint32 currentCycle = (block.timestamp.safeCastTo32() / gaugeCycleLength) * gaugeCycleLength;
        uint32 lastCycle = gaugeCycle;

        // ensure new cycle has begun
        if (currentCycle <= lastCycle) revert CycleError();

        if (currentCycle > nextCycle) {
            nextCycle = currentCycle;
            paginationOffset = 0;
        }

        uint32 offset = paginationOffset;

        // important to only calculate the reward amount once to prevent each page from having a different reward amount
        if (offset == 0) {
            // queue the rewards stream and sanity check the tokens were received
            uint256 balanceBefore = rewardToken.balanceOf(address(this));
            uint256 newRewards = rewardsStream.getRewards();
            require(rewardToken.balanceOf(address(this)) - balanceBefore >= newRewards);
            require(newRewards <= type(uint112).max); // safe cast
            nextCycleQueuedRewards += uint112(newRewards); // in case a previous incomplete cycle had rewards, add on
        }

        uint112 queued = nextCycleQueuedRewards;

        uint256 remaining = gaugeToken.numGauges() - offset;

        // Important to do non-strict inequality to include the case where the numRewards is just enough to complete the cycle
        if (remaining <= numRewards) {
            numRewards = remaining;
            gaugeCycle = currentCycle;
            nextCycleQueuedRewards = 0;
            paginationOffset = 0;
            emit CycleStart(currentCycle, queued);
        } else {
            paginationOffset = offset + numRewards.safeCastTo32();
        }

        // iterate over all gauges and update the rewards allocations
        address[] memory gauges = gaugeToken.gauges(offset, numRewards);

        _queueRewards(gauges, currentCycle, lastCycle, queued);
    }

    function _queueRewards(
        address[] memory gauges,
        uint32 currentCycle,
        uint32 lastCycle,
        uint256 totalQueuedForCycle
    ) internal {
        uint256 size = gauges.length;

        if (size == 0) revert EmptyGaugesError();

        for (uint256 i = 0; i < size; i++) {
            ERC20 gauge = ERC20(gauges[i]);

            QueuedRewards memory queuedRewards = gaugeQueuedRewards[gauge];

            // Cycle queue already started
            require(queuedRewards.storedCycle < currentCycle);
            assert(queuedRewards.storedCycle == 0 || queuedRewards.storedCycle >= lastCycle);
            // SWC-110-Assert Violation: L198
            uint112 completedRewards = queuedRewards.storedCycle == lastCycle ? queuedRewards.cycleRewards : 0;
            uint256 nextRewards = gaugeToken.calculateGaugeAllocation(address(gauge), totalQueuedForCycle);
            require(nextRewards <= type(uint112).max); // safe cast

            gaugeQueuedRewards[gauge] = QueuedRewards({
                priorCycleRewards: queuedRewards.priorCycleRewards + completedRewards,
                cycleRewards: uint112(nextRewards),
                storedCycle: currentCycle
            });

            emit QueueRewards(address(gauge), currentCycle, nextRewards);
        }
    }

    /**
     @notice calculate and transfer accrued rewards to flywheel core
     @param gauge the gauge to accrue rewards for
     @param lastUpdatedTimestamp the last updated time for gauge
     @return accruedRewards the amount of reward tokens accrued.
    */
    function getAccruedRewards(ERC20 gauge, uint32 lastUpdatedTimestamp)
        external
        override
        onlyFlywheel
        returns (uint256 accruedRewards)
    {
        QueuedRewards memory queuedRewards = gaugeQueuedRewards[gauge];

        uint32 cycle = gaugeCycle;
        bool incompleteCycle = queuedRewards.storedCycle > cycle;

        // no rewards
        if (queuedRewards.priorCycleRewards == 0 && (queuedRewards.cycleRewards == 0 || incompleteCycle)) {
            return 0;
        }

        // if stored cycle != 0 it must be >= the last queued cycle
        assert(queuedRewards.storedCycle >= cycle);

        uint32 cycleEnd = cycle + gaugeCycleLength;

        // always accrue prior rewards
        accruedRewards = queuedRewards.priorCycleRewards;
        uint112 cycleRewardsNext = queuedRewards.cycleRewards;

        if (incompleteCycle) {
            // If current cycle queue incomplete, do nothing to current cycle rewards or accrued
        } else if (block.timestamp >= cycleEnd) {
            // If cycle ended, accrue all rewards
            accruedRewards += cycleRewardsNext;
            cycleRewardsNext = 0;
        } else {
            uint32 beginning = lastUpdatedTimestamp > cycle ? lastUpdatedTimestamp : cycle;

            // otherwise, return proportion of remaining rewards in cycle
            uint32 elapsed = block.timestamp.safeCastTo32() - beginning;
            uint32 remaining = cycleEnd - beginning;

            // Casted up to avoid intermediate overflow
            // cannot end in an overflow of uint112 because elapsed <= remaining and cycleRewards <= uint112.max
            uint256 currentAccrued = (uint256(queuedRewards.cycleRewards) * elapsed) / remaining;

            // add proportion of current cycle to accrued rewards
            accruedRewards += currentAccrued;
            cycleRewardsNext -= uint112(currentAccrued);
        }

        gaugeQueuedRewards[gauge] = QueuedRewards({
            priorCycleRewards: 0,
            cycleRewards: cycleRewardsNext,
            storedCycle: queuedRewards.storedCycle
        });
    }

    /// @notice set the rewards stream contract
    function setRewardsStream(IRewardsStream newRewardsStream) external requiresAuth {
        rewardsStream = newRewardsStream;
    }
}
