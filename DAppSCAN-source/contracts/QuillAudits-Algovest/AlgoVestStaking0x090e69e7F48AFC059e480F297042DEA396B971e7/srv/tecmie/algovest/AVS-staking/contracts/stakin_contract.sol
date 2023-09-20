// SPDX-License-Identifier: MIT
// File: node_modules@openzeppelin\contracts\token\ERC20\IERC20.sol
// File: node_modules@openzeppelin\contracts\math\SafeMath.sol
// SWC-103-Floating Pragma: L5
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AlgoVestStaking is Ownable {
    using SafeMath for uint256;
    IERC20 public avsAddress;
    uint256 public zeroDayStartTime;
    uint256 public dayDurationSec;

    modifier onlyWhenOpen {
        require(
            now >= zeroDayStartTime,
            "StakingAVS: Contract is not open yet"
        );
        _;
    }

    uint256 public allAVSTokens;
    uint256 public totalStakers;
    uint256 public totalStakedAVS;
    uint256 public unfreezedAVSTokens;
    uint256 public freezedAVSTokens;
    event AVSTokenIncome(address who, uint256 amount, uint256 day);
    event AVSTokenOutcome(address who, uint256 amount, uint256 day);
    event TokenFreezed(address who, uint256 amount, uint256 day);
    event TokenUnfreezed(address who, uint256 amount, uint256 day);

    uint256 public stakeIdLast;
    uint256 public constant maxNumDays = 180;
    struct StakeInfo {
        uint256 stakeId;
        uint256 startDay;
        uint256 numDaysStake;
        uint256 stakedAVS;
        uint256 freezedRewardAVSTokens;
    }
    mapping(address => StakeInfo[]) public stakeList;
    event StakeStart(
        address who,
        uint256 AVSIncome,
        uint256 AVSEarnings,
        uint256 numDays,
        uint256 day,
        uint256 stakeId
    );
    event StakeEnd(
        address who,
        uint256 stakeId,
        uint256 AVSEarnings,
        uint256 servedNumDays,
        uint256 day
    );
    StakeInfo[] public allStakes;

    //event sev_days(uint256 counter, uint256 day_week_ago, uint256 final_perc);
    constructor(
        IERC20 _AVSAddress,
        uint256 _zeroDayStartTime,
        uint256 _dayDurationSec
    ) public {
        avsAddress = _AVSAddress;
        zeroDayStartTime = _zeroDayStartTime;
        dayDurationSec = _dayDurationSec;
    }

// SWC-107-Reentrancy: L74 - L84
    function AVSTokenDonation(uint256 amount) external {
        address sender = _msgSender();
        require(
            avsAddress.transferFrom(sender, address(this), amount),
            "StakingAVS: Could not get AVS tokens"
        );
        allAVSTokens = allAVSTokens.add(amount);
        unfreezedAVSTokens = unfreezedAVSTokens.add(amount);
        emit AVSTokenIncome(sender, amount, _currentDay());
    }

    function AVSOwnerWithdraw(uint256 amount) external onlyOwner {
        address sender = _msgSender();
        require(sender == owner(), "StakingAVS: Sender is not owner");
        require(
            allAVSTokens >= amount,
            "StakingAVS: Not enough value on this contract"
        );
        require(
            unfreezedAVSTokens >= amount,
            "StakingAVS: Not enough unfreezed value on this contract"
        );
        require(
            avsAddress.transfer(sender, amount),
            "StakingAVS: Could not send AVS tokens"
        );
        allAVSTokens = allAVSTokens.sub(amount);
        unfreezedAVSTokens = unfreezedAVSTokens.sub(amount);
        emit AVSTokenOutcome(sender, amount, _currentDay());
    }

    function stakeStart(uint256 amount, uint256 numDaysStake)
        external
        onlyWhenOpen
    {
        require(
            numDaysStake > 0 &&
                numDaysStake <= maxNumDays &&
                numDaysStake % 15 == 0,
            "StakingAVS: Wrong number of days"
        );
        address sender = _msgSender();
        require(
            avsAddress.transferFrom(sender, address(this), amount),
            "StakingAVS: AVS token transfer failed"
        );
        uint256 currDay = _currentDay();
        emit AVSTokenIncome(sender, amount, currDay);
        uint256 avsEarnings = _getAVSEarnings(amount, numDaysStake);
        // Freeze AVS tokens on contract
        require(
            unfreezedAVSTokens >= avsEarnings - amount,
            "StakingAVS: Insufficient funds of AVS tokens to this stake"
        );
        unfreezedAVSTokens = unfreezedAVSTokens.sub(avsEarnings - amount);
        freezedAVSTokens = freezedAVSTokens.add(avsEarnings - amount);
        emit TokenFreezed(sender, avsEarnings - amount, currDay);
        // Add stake into stakeList
        StakeInfo memory st =
            StakeInfo(
                ++stakeIdLast,
                currDay,
                numDaysStake,
                amount,
                avsEarnings - amount
            );
        stakeList[sender].push(st);
        allStakes.push(st);
        emit StakeStart(
            sender,
            amount,
            avsEarnings - amount,
            numDaysStake,
            currDay,
            stakeIdLast
        );
        if (stakeList[sender].length == 1) {
            ++totalStakers;
        }
        totalStakedAVS = totalStakedAVS.add(amount);
    }

    function stakeEnd(uint256 stakeIndex, uint256 stakeId)
        external
        onlyWhenOpen
    {
        address sender = _msgSender();
        require(
            stakeIndex >= 0 && stakeIndex < stakeList[sender].length,
            "StakingAVS: Wrong stakeIndex"
        );
        StakeInfo storage st = stakeList[sender][stakeIndex];
        require(st.stakeId == stakeId, "StakingAVS: Wrong stakeId");
        uint256 currDay = _currentDay();
        uint256 servedNumOfDays = min(currDay - st.startDay, st.numDaysStake);
        if (servedNumOfDays < st.numDaysStake) {
            uint256 avsTokensToReturn =
                _getAVSEarnings_pen(st.stakedAVS, servedNumOfDays);
            require(
                st.freezedRewardAVSTokens >= avsTokensToReturn - st.stakedAVS,
                "StakingAVS: Internal error!"
            );
            uint256 remainingAVSTokens =
                st.freezedRewardAVSTokens.sub(avsTokensToReturn - st.stakedAVS);
            unfreezedAVSTokens = unfreezedAVSTokens.add(remainingAVSTokens);
            freezedAVSTokens = freezedAVSTokens.sub(st.freezedRewardAVSTokens);
            emit TokenUnfreezed(sender, st.freezedRewardAVSTokens, currDay);
            allAVSTokens = allAVSTokens.sub(avsTokensToReturn - st.stakedAVS);
            avsAddress.transfer(sender, avsTokensToReturn);
            emit AVSTokenOutcome(
                sender,
                avsTokensToReturn - st.stakedAVS,
                currDay
            );
            emit StakeEnd(
                sender,
                st.stakeId,
                avsTokensToReturn - st.stakedAVS,
                servedNumOfDays,
                currDay
            );
            _removeStake(stakeIndex, stakeId);
            if (stakeList[sender].length == 0) {
                --totalStakers;
            }
            totalStakedAVS = totalStakedAVS.sub(st.stakedAVS);
        } else {
            uint256 avsTokensToReturn =
                _getAVSEarnings(st.stakedAVS, st.numDaysStake);
            require(
                st.freezedRewardAVSTokens >= avsTokensToReturn - st.stakedAVS,
                "StakingAVS: Internal error!"
            );
            uint256 remainingAVSTokens =
                st.freezedRewardAVSTokens.sub(avsTokensToReturn - st.stakedAVS);
            unfreezedAVSTokens = unfreezedAVSTokens.add(remainingAVSTokens);
            freezedAVSTokens = freezedAVSTokens.sub(st.freezedRewardAVSTokens);
            emit TokenUnfreezed(sender, st.freezedRewardAVSTokens, currDay);
            allAVSTokens = allAVSTokens.sub(avsTokensToReturn - st.stakedAVS);
            //avsAddress.transfer(sender, avsTokensToReturn);
            avsAddress.transfer(
                sender,
                st.stakedAVS.add(
                    (avsTokensToReturn.sub(st.stakedAVS)).mul(98).div(100)
                )
            );
            emit AVSTokenOutcome(
                sender,
                (avsTokensToReturn.sub(st.stakedAVS)).mul(98).div(100),
                currDay
            );

            emit StakeEnd(
                sender,
                st.stakeId,
                avsTokensToReturn - st.stakedAVS,
                servedNumOfDays,
                currDay
            );
            _removeStake(stakeIndex, stakeId);
            if (stakeList[sender].length == 0) {
                --totalStakers;
            }
            totalStakedAVS = totalStakedAVS.sub(st.stakedAVS);
        }
        /*uint256 avsTokensToReturn = _getAvsEarnings(st.stakedAVS, servedNumOfDays);
        require(
            st.freezedRewardAVSTokens >= avsTokensToReturn,
            "StakingAVS: Internal error!"
        );*/

        /*uint256 remainingAVSTokens = st.freezedRewardAVSTokens.sub(avsTokensToReturn);
        unfreezedAVSTokens = unfreezedAVSTokens.add(remainingAVSTokens);
        freezedAVSTokens = freezedAVSTokens.sub(st.freezedRewardAVSTokens);
        emit TokenUnfreezed(sender, st.freezedRewardAVSTokens, currDay);
        allAVSTokens = allAVSTokens.sub(avsTokensToReturn);
        avsAddress.transfer(sender, avsTokensToReturn);
        emit AVSTokenOutcome(sender, avsTokensToReturn, currDay);

        emit StakeEnd(
            sender,
            st.stakeId,
            avsTokensToReturn,
            servedNumOfDays,
            currDay
        );
        _removeStake(stakeIndex, stakeId);*/
    }

    function stakeListCount(address who) external view returns (uint256) {
        return stakeList[who].length;
    }

    function currentDay() external view onlyWhenOpen returns (uint256) {
        return _currentDay();
    }

    function getDayUnixTime(uint256 day) public view returns (uint256) {
        return zeroDayStartTime.add(day.mul(dayDurationSec));
    }

    /*function changeDaysApyPercents(
        uint256 day,
        uint256 numerator,
        uint256 denominator
    )
        external
        onlyOwner
    {
        require(
            day > 0 && day <= maxNumDays,
            "StakingAVS: Wrong day"
        );
        DaysApyPercentsNumerator[day.sub(1)] = numerator;
        DaysApyPercentsDenominator[day.sub(1)] = denominator;
        _testDaysApyPercents();
    }*/

    function getEndDayOfStakeInUnixTime(
        address who,
        uint256 stakeIndex,
        uint256 stakeId
    ) external view returns (uint256) {
        require(
            stakeIndex < stakeList[who].length,
            "StakingAVS: Wrong stakeIndex"
        );
        require(
            stakeId == stakeList[who][stakeIndex].stakeId,
            "StakingAVS: Wrong stakeId"
        );

        return
            getDayUnixTime(
                stakeList[who][stakeIndex].startDay.add(
                    stakeList[who][stakeIndex].numDaysStake
                )
            );
    }

    function getStakeDivsNow(
        address who,
        uint256 stakeIndex,
        uint256 stakeId
    ) external view returns (uint256) {
        require(
            stakeIndex < stakeList[who].length,
            "StakingAVS: Wrong stakeIndex"
        );
        require(
            stakeId == stakeList[who][stakeIndex].stakeId,
            "StakingAVS: Wrong stakeId"
        );

        uint256 currDay = _currentDay();
        uint256 servedDays =
            _getServedDays(
                currDay,
                stakeList[who][stakeIndex].startDay,
                stakeList[who][stakeIndex].numDaysStake
            );
        return
            _getAVSEarnings(stakeList[who][stakeIndex].stakedAVS, servedDays);
    }

    function _getServedDays(
        uint256 currDay,
        uint256 startDay,
        uint256 numDaysStake
    ) private pure returns (uint256 servedDays) {
        servedDays = currDay.sub(startDay);
        if (servedDays > numDaysStake) servedDays = numDaysStake;
    }

    function _getAVSEarnings(uint256 avsAmount, uint256 numOfDays)
        private
        view
        returns (uint256 reward)
    {
        require(
            numOfDays >= 0 && numOfDays <= maxNumDays,
            "StakingAVS: Wrong numOfDays"
        );
        uint256 num_of_parts = numOfDays.div(15);
        uint256 perc = 1000;
        //ufixed percent = perc.mul((104/100)**num_of_parts).mul(numOfDays).div(365);
        for (uint256 i = 2; i <= num_of_parts; ++i) {
            perc += perc.mul(10).div(100);
        }
        /*for (uint256 day = 1; day <= numOfDays; ++day)
        {
            reward +=
                avsAmount.add(reward)
                    .mul(DaysApyPercentsNumerator[day - 1])
                    .div(daysInYear)
                    .div(DaysApyPercentsDenominator[day - 1]);
        }*/
        return
            avsAmount +
            avsAmount.mul(perc).div(10000).mul(uint256(numOfDays)).div(
                uint256(365)
            );
    }

    function _getAVSEarnings_pen(uint256 avsAmount, uint256 numOfDays)
        private
        view
        returns (uint256 reward)
    {
        require(
            numOfDays >= 0 && numOfDays <= maxNumDays,
            "StakingAVS: Wrong numOfDays"
        );
        uint256 num_of_parts = numOfDays.div(15);
        //uint256 percent = 10*(1.04**num_of_parts)*numOfDays/365;
        uint256 perc = 1000;
        for (uint256 i = 2; i <= num_of_parts; ++i) {
            perc += perc.mul(10).div(100);
        }
        uint256 rew =
            avsAmount.mul(perc).div(10000).mul(uint256(numOfDays)).div(
                uint256(365)
            );
        //uint256 rew = avsAmount.mul(perc).div(100).mul(uint256(num_of_parts)).mul(15).div(uint256(365)); если надо будет поменять
        return avsAmount + (rew * uint256(80)) / uint256(100);
    }

    function _currentDay() private view returns (uint256) {
        return now.sub(zeroDayStartTime).div(dayDurationSec);
    }

    function _removeStake(uint256 stakeIndex, uint256 stakeId) private {
        address sender = _msgSender();
        uint256 stakeListLength = stakeList[sender].length;
        require(
            stakeIndex >= 0 && stakeIndex < stakeListLength,
            "StakingAVS: Wrong stakeIndex"
        );
        StakeInfo storage st = stakeList[sender][stakeIndex];
        require(st.stakeId == stakeId, "StakingAVS: Wrong stakeId");
        if (stakeIndex < stakeListLength - 1)
            stakeList[sender][stakeIndex] = stakeList[sender][
                stakeListLength - 1
            ];
        stakeList[sender].pop();
    }

    function min(uint256 a, uint256 b) private view returns (uint256 minimum) {
        //uint256 minimum;
        if (a > b) {
            minimum = b;
        } else {
            minimum = a;
        }
        return minimum;
    }

    function length_stakes() external view returns (uint256) {
        return allStakes.length;
    }

    function seven_days() external view returns (uint256) {
        if (allStakes.length == 0) {
            return 0;
        }
        uint256 day_now = _currentDay();
        uint256 days_in_week = 7;
        uint256 day_week_ago = 0;
        uint256 counter = 0;
        uint256 all_percents = 0;
        uint256 step = allStakes.length.sub(1);
        uint256 stake_day = allStakes[step].startDay;
        uint256 num_stake_days = allStakes[step].numDaysStake;
        if (day_now >= days_in_week) {
            day_week_ago = day_now - days_in_week;
        }
        while (stake_day >= day_week_ago && step >= 0) {
            uint256 num_of_parts = num_stake_days.div(15);
            uint256 perc = 1000;
            for (uint256 i = 2; i <= num_of_parts; ++i) {
                perc = perc.add(perc.mul(10).div(100));
            }
            all_percents = all_percents.add(perc);
            counter = counter.add(1);
            if (step != 0) {
                step = step.sub(1);
            } else {
                break;
            }
            stake_day = allStakes[step].startDay;
            num_stake_days = allStakes[step].numDaysStake;
        }
        uint256 final_percent = all_percents.div(counter);
        //emit sev_days(counter, day_week_ago, final_percent);
        return final_percent;
    }
}
