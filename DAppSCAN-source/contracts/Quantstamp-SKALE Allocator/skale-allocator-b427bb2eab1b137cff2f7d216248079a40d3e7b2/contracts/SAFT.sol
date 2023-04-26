// SPDX-License-Identifier: AGPL-3.0-only

/*
    SAFT.sol - SKALE SAFT Core
    Copyright (C) 2020-Present SKALE Labs
    @author Artem Payvin

    SKALE SAFT Core is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE SAFT Core is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE SAFT Core.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "./interfaces/delegation/ILocker.sol";
import "./interfaces/ITimeHelpers.sol";
import "./Permissions.sol";

/**
 * @title SAFT
 * @dev This contract manages SKALE investor tokens based on the Simple
 * Agreement for Future Tokens (SAFT).
 *
 * An investor (holder) may participate in multiple SAFT rounds.
 *
 * A SAFT is defined by an initial token lock period, followed by periodic
 * unlocking.
 *
 * The process to onboard SAFT holders is as follows:
 *
 * 1- SAFT holders are registered to a SAFT by SKALE or ConsenSys Activate.
 * 2- SAFT holders approve their address.
 * 3- SKALE then activates each holder.
 */
contract SAFT is ILocker, Permissions, IERC777Recipient {

    enum TimeLine {DAY, MONTH, YEAR}

    struct SAFTRound {
        uint fullPeriod;
        uint lockupPeriod; // months
        TimeLine vestingPeriod;
        uint regularPaymentTime; // amount of days/months/years
    }

    struct SaftHolder {
        bool registered;
        bool approved;
        bool active;
        uint saftRoundId;
        uint startVestingTime;
        uint fullAmount;
        uint afterLockupAmount;
    }

    event SaftRoundCreated(
        uint id
    );

    bytes32 public constant ACTIVATE_ROLE = keccak256("ACTIVATE_ROLE");

    IERC1820Registry private _erc1820;

    // array of SAFT configs
    SAFTRound[] private _saftRounds;
    // SAFTRound[] private _otherPlans;

    //        holder => SAFT holder params
    mapping (address => SaftHolder) private _vestingHolders;

    //           holder => address of vesting escrow
    // mapping (address => address) private _holderToEscrow;

    modifier onlyOwnerAndActivate() {
        require(_isOwner() || hasRole(ACTIVATE_ROLE, _msgSender()), "Not authorized");
        _;
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    )
        external override
        allow("SkaleToken")
        // solhint-disable-next-line no-empty-blocks
    {

    }

    /**
     * @dev Allows `msg.sender` to approve their address as a SAFT holder.
     *
     * Requirements:
     *
     * - Holder address must be already registered.
     * - Holder address must not already be approved.
     */
    function approveSAFTHolder() external {
        address holder = msg.sender;
        require(_vestingHolders[holder].registered, "SAFT is not registered");
        require(!_vestingHolders[holder].approved, "SAFT is already approved");
        _vestingHolders[holder].approved = true;
    }

    /**
     * @dev Allows Owner to activate a holder address and transfers locked
     * tokens to a holder address.
     *
     * Requirements:
     *
     * - Holder address must be already registered.
     * - Holder address must be approved.
     */
    function startUnlocking(address holder) external onlyOwner {
        require(_vestingHolders[holder].registered, "SAFT is not registered");
        require(_vestingHolders[holder].approved, "SAFT is not approved");
        _vestingHolders[holder].active = true;
        require(
            IERC20(contractManager.getContract("SkaleToken")).transfer(
                holder,
                _vestingHolders[holder].fullAmount
            ),
            "Error of token sending"
        );
    }

    /**
     * @dev Allows Owner to define and add a SAFT round.
     *
     * Requirements:
     *
     * - Lockup period must be less than or equal to the full period.
     * - Locked period must be in days, months, or years.
     * - The full period must equal the lock period plus the unlock schedule.
     */
    function addSAFTRound(
        uint lockupPeriod, // months
        uint fullPeriod, // months
        uint8 vestingPeriod, // 1 - day 2 - month 3 - year
        uint vestingTimes // months or days or years
    )
        external
        onlyOwner
    {
        require(fullPeriod >= lockupPeriod, "Incorrect periods");
        require(vestingPeriod >= 1 && vestingPeriod <= 3, "Incorrect vesting period");
        require(
            (fullPeriod - lockupPeriod) == vestingTimes ||
            ((fullPeriod - lockupPeriod) / vestingTimes) * vestingTimes == fullPeriod - lockupPeriod,
            "Incorrect vesting times"
        );
        _saftRounds.push(SAFTRound({
            fullPeriod: fullPeriod,
            lockupPeriod: lockupPeriod,
            vestingPeriod: TimeLine(vestingPeriod - 1),
            regularPaymentTime: vestingTimes
        }));

        emit SaftRoundCreated(_saftRounds.length - 1);
    }

    /**
     * @dev Allows Owner and Activate to register a holder to a SAFT round.
     *
     * Requirements:
     *
     * - SAFT round must already exist.
     * - The lockup amount must be less than or equal to the full allocation.
     * - The start date for unlocking must not have already passed.
     * - The holder address must not already be included in this SAFT round.
     */
    function connectHolderToSAFT(
        address holder,
        uint saftRoundId,
        uint startVestingTime, // timestamp
        uint fullAmount,
        uint lockupAmount
    )
        external
        onlyOwnerAndActivate
    {
        // TOOD: Fix index error
        require(_saftRounds.length >= saftRoundId && saftRoundId > 0, "SAFT round does not exist");
        require(fullAmount >= lockupAmount, "Incorrect amounts");
        require(startVestingTime <= now, "Incorrect period starts");
        require(!_vestingHolders[holder].registered, "SAFT holder is already added");
        _vestingHolders[holder] = SaftHolder({
            registered: true,
            approved: false,
            active: false,
            saftRoundId: saftRoundId,
            startVestingTime: startVestingTime,
            fullAmount: fullAmount,
            afterLockupAmount: lockupAmount
        });
        // if (connectHolderToEscrow) {
        //     _holderToEscrow[holder] = address(new CoreEscrow(address(contractManager), holder));
        // } else {
        //     _holderToEscrow[holder] = holder;
        // }
    }

    /**
     * @dev Updates and returns the current locked amount of tokens.
     */
    function getAndUpdateLockedAmount(address wallet) external override returns (uint) {
        if (! _vestingHolders[wallet].active) {
            return 0;
        }
        return getLockedAmount(wallet);
    }

    /**
     * @dev Updates and returns the slashed amount of tokens.
     */
    function getAndUpdateForbiddenForDelegationAmount(address) external override returns (uint) {
        // network_launch_timestamp
        return 0;
    }

    /**
     * @dev Returns the start time of the SAFT.
     */
    function getStartVestingTime(address holder) external view returns (uint) {
        return _vestingHolders[holder].startVestingTime;
    }

    /**
     * @dev Returns the time of final unlock.
     */
    function getFinishVestingTime(address holder) external view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        SaftHolder memory saftHolder = _vestingHolders[holder];
        SAFTRound memory saftParams = _saftRounds[saftHolder.saftRoundId - 1];
        return timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.fullPeriod);
    }

    /**
     * @dev Returns the lockup period in months.
     */
    function getLockupPeriodInMonth(address holder) external view returns (uint) {
        return _saftRounds[_vestingHolders[holder].saftRoundId - 1].lockupPeriod;
    }

    /**
     * @dev Confirms whether the holder is in an active state.
     */
    function isActiveVestingTerm(address holder) external view returns (bool) {
        return _vestingHolders[holder].active;
    }

    /**
     * @dev Confirms whether the holder is approved in a SAFT round.
     */
    function isApprovedSAFT(address holder) external view returns (bool) {
        return _vestingHolders[holder].approved;
    }

    /**
     * @dev Confirms whether the holder is in a registered state.
     */
    function isSAFTRegistered(address holder) external view returns (bool) {
        return _vestingHolders[holder].registered;
    }

    /**
     * @dev Returns the locked and unlocked (full) amount of tokens allocated to
     * the holder address in SAFT.
     */
    function getFullAmount(address holder) external view returns (uint) {
        return _vestingHolders[holder].fullAmount;
    }

    /**
     * @dev Returns the timestamp when lockup period ends and periodic unlocking
     * begins.
     */
    function getLockupPeriodTimestamp(address holder) external view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        SaftHolder memory saftHolder = _vestingHolders[holder];
        SAFTRound memory saftParams = _saftRounds[saftHolder.saftRoundId - 1];
        return timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.lockupPeriod);
    }

    /**
     * @dev Returns the time of next unlock.
     */
    function getTimeOfNextUnlock(address holder) external view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        uint date = now;
        SaftHolder memory saftHolder = _vestingHolders[holder];
        SAFTRound memory saftParams = _saftRounds[saftHolder.saftRoundId - 1];
        uint lockupDate = timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.lockupPeriod);
        if (date < lockupDate) {
            return lockupDate;
        }
        uint dateTime = _getTimePointInCorrectPeriod(date, saftParams.vestingPeriod);
        uint lockupTime = _getTimePointInCorrectPeriod(
            timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.lockupPeriod),
            saftParams.vestingPeriod
        );
        uint finishTime = _getTimePointInCorrectPeriod(
            timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.fullPeriod),
            saftParams.vestingPeriod
        );
        uint numberOfDonePayments = dateTime.sub(lockupTime).div(saftParams.regularPaymentTime);
        uint numberOfAllPayments = finishTime.sub(lockupTime).div(saftParams.regularPaymentTime);
        if (numberOfAllPayments <= numberOfDonePayments + 1) {
            return timeHelpers.addMonths(
                saftHolder.startVestingTime,
                saftParams.fullPeriod
            );
        }
        uint nextPayment = finishTime
            .sub(
                saftParams.regularPaymentTime.mul(numberOfAllPayments.sub(numberOfDonePayments + 1))
            );
        return _addMonthsAndTimePoint(lockupDate, nextPayment - lockupTime, saftParams.vestingPeriod);
    }

    /**
     * @dev Returns the SAFT round parameters.
     *
     * Requirements:
     *
     * - SAFT round must already exist.
     */
    function getSAFTRound(uint saftRoundId) external view returns (SAFTRound memory) {
        require(saftRoundId > 0 && saftRoundId <= _saftRounds.length, "SAFT Round does not exist");
        return _saftRounds[saftRoundId - 1];
    }

    /**
     * @dev Returns the SAFT round parameters for a holder address.
     *
     * Requirements:
     *
     * - Holder address must be registered to a SAFT.
     */
    function getSAFTHolderParams(address holder) external view returns (SaftHolder memory) {
        require(_vestingHolders[holder].registered, "SAFT holder is not registered");
        return _vestingHolders[holder];
    }

    function initialize(address contractManagerAddress) public override initializer {
        Permissions.initialize(contractManagerAddress);
        // vestingManager = msg.sender;
        _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
    }

    /**
     * @dev Returns the locked amount of tokens.
     */
    function getLockedAmount(address wallet) public view returns (uint) {
        return _vestingHolders[wallet].fullAmount - calculateUnlockedAmount(wallet);
    }

    /**
     * @dev Calculates and returns the amount of unlocked tokens.
     */
    function calculateUnlockedAmount(address wallet) public view returns (uint unlockedAmount) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        uint date = now;
        SaftHolder memory saftHolder = _vestingHolders[wallet];
        SAFTRound memory saftParams = _saftRounds[saftHolder.saftRoundId - 1];
        unlockedAmount = 0;
        if (date >= timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.lockupPeriod)) {
            unlockedAmount = saftHolder.afterLockupAmount;
            if (date >= timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.fullPeriod)) {
                unlockedAmount = saftHolder.fullAmount;
            } else {
                uint partPayment = _getPartPayment(wallet, saftHolder.fullAmount, saftHolder.afterLockupAmount);
                unlockedAmount = unlockedAmount.add(partPayment.mul(_getNumberOfCompletedUnlocks(wallet)));
            }
        }
    }

    /**
     * @dev Returns the number of unlocking events that have occurred.
     */
    function _getNumberOfCompletedUnlocks(address wallet) internal view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        uint date = now;
        SaftHolder memory saftHolder = _vestingHolders[wallet];
        SAFTRound memory saftParams = _saftRounds[saftHolder.saftRoundId - 1];
        // if (date < timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.lockupPeriod)) {
        //     return 0;
        // }
        uint dateTime = _getTimePointInCorrectPeriod(date, saftParams.vestingPeriod);
        uint lockupTime = _getTimePointInCorrectPeriod(
            timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.lockupPeriod),
            saftParams.vestingPeriod
        );
        return dateTime.sub(lockupTime).div(saftParams.regularPaymentTime);
    }

    /**
     * @dev Returns the total number of unlocking events.
     */
    function _getNumberOfAllUnlocks(address wallet) internal view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        SaftHolder memory saftHolder = _vestingHolders[wallet];
        SAFTRound memory saftParams = _saftRounds[saftHolder.saftRoundId - 1];
        uint finishTime = _getTimePointInCorrectPeriod(
            timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.fullPeriod),
            saftParams.vestingPeriod
        );
        uint afterLockupTime = _getTimePointInCorrectPeriod(
            timeHelpers.addMonths(saftHolder.startVestingTime, saftParams.lockupPeriod),
            saftParams.vestingPeriod
        );
        return finishTime.sub(afterLockupTime).div(saftParams.regularPaymentTime);
    }

    /**
     * @dev Returns the amount of tokens that are unlocked in each unlocking
     * period.
     */
    function _getPartPayment(
        address wallet,
        uint fullAmount,
        uint afterLockupPeriodAmount
    )
        internal
        view
        returns(uint)
    {
        return fullAmount.sub(afterLockupPeriodAmount).div(_getNumberOfAllUnlocks(wallet));
    }

    /**
     * @dev Returns timestamp when adding timepoints (days/months/years) to
     * timestamp.
     */
    function _getTimePointInCorrectPeriod(uint timestamp, TimeLine vestingPeriod) private view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        if (vestingPeriod == TimeLine.DAY) {
            return timeHelpers.timestampToDay(timestamp);
        } else if (vestingPeriod == TimeLine.MONTH) {
            return timeHelpers.timestampToMonth(timestamp);
        } else {
            return timeHelpers.timestampToYear(timestamp);
        }
    }

    /**
     * @dev Returns timepoints (days/months/years) from a given timestamp.
     */
    function _addMonthsAndTimePoint(
        uint timestamp,
        uint timePoints,
        TimeLine vestingPeriod
    )
        private
        view
        returns (uint)
    {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        if (vestingPeriod == TimeLine.DAY) {
            return timeHelpers.addDays(timestamp, timePoints);
        } else if (vestingPeriod == TimeLine.MONTH) {
            return timeHelpers.addMonths(timestamp, timePoints);
        } else {
            return timeHelpers.addYears(timestamp, timePoints);
        }
    }
}