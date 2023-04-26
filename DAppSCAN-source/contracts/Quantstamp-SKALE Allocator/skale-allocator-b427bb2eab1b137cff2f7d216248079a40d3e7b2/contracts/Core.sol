// SPDX-License-Identifier: AGPL-3.0-only

/*
    Core.sol - SKALE SAFT Core
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
import "./interfaces/openzeppelin/IProxyFactory.sol";
import "./interfaces/openzeppelin/IProxyAdmin.sol";
import "./interfaces/ITimeHelpers.sol";
import "./CoreEscrow.sol";
import "./Permissions.sol";

/**
 * @title Core
 * @dev This contract manages SKALE Employee Token Option Plans.
 *
 * An employee may have multiple holdings under an Core.
 *
 * An Core is defined by an initial token vesting cliff period, followed by
 * periodic vesting.
 *
 * Employees (holders) may be registered into a particular plan, and be assigned
 * individual start states and allocations.
 */
contract Core is Permissions, IERC777Recipient {

    enum TimeLine {DAY, MONTH, YEAR}

    enum HolderStatus {
        UNKNOWN,
        CONFIRMATION_PENDING,
        CONFIRMED,
        ACTIVE,
        TERMINATED
    }

    struct Plan {
        uint fullPeriod;
        uint vestingCliffPeriod; // months
        TimeLine vestingPeriod;
        uint regularPaymentTime; // amount of days/months/years
        bool isUnvestedDelegatable;
    }

    struct PlanHolder {
        HolderStatus status;
        uint planId;
        uint startVestingTime;
        uint fullAmount;
        uint afterLockupAmount;
    }

    event PlanCreated(
        uint id
    );

    IERC1820Registry private _erc1820;

    // array of Plan configs
    Plan[] private _allPlans;

    address public vestingManager;

    // mapping (address => uint) private _vestedAmount;

    //        holder => Plan holder params
    mapping (address => PlanHolder) private _vestingHolders;

    //        holder => address of Core escrow
    mapping (address => CoreEscrow) private _holderToEscrow;

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
     * @dev Allows `msg.sender` to approve their address as an Core holder.
     *
     * Requirements:
     *
     * - Holder address must be already registered.
     * - Holder address must not already be approved.
     */
    function approveHolder() external {
        address holder = msg.sender;
        require(_vestingHolders[holder].status != HolderStatus.UNKNOWN, "Holder is not registered");
        require(_vestingHolders[holder].status == HolderStatus.CONFIRMATION_PENDING, "Holder is already approved");
        _vestingHolders[holder].status = HolderStatus.CONFIRMED;
    }

    /**
     * @dev Allows Owner to activate a holder address and transfer locked
     * tokens to the associated Core escrow address.
     *
     * Requirements:
     *
     * - Holder address must be already confirmed.
     */
    function startVesting(address holder) external onlyOwner {
        require(_vestingHolders[holder].status == HolderStatus.CONFIRMED, "Holder address is not confirmed");
        _vestingHolders[holder].status = HolderStatus.ACTIVE;
        require(
            IERC20(contractManager.getContract("SkaleToken")).transfer(
                address(_holderToEscrow[holder]),
                _vestingHolders[holder].fullAmount
            ),
            "Error of token sending"
        );
    }

    /**
     * @dev Allows Owner to define and add an Core.
     *
     * Requirements:
     *
     * - Vesting cliff period must be less than or equal to the full period.
     * - Vesting period must be in days, months, or years.
     * - Full period must equal vesting cliff plus entire vesting schedule.
     */
    function addCore(
        uint vestingCliffPeriod, // months
        uint fullPeriod, // months
        uint8 vestingPeriod, // 1 - day 2 - month 3 - year
        uint vestingTimes, // months or days or years
        bool isUnvestedDelegatable // can holder delegate all un-vested tokens
    )
        external
        onlyOwner
    {
        require(fullPeriod >= vestingCliffPeriod, "Cliff period exceeds full period");
        require(vestingPeriod >= 1 && vestingPeriod <= 3, "Incorrect vesting period");
        require(
            (fullPeriod - vestingCliffPeriod) == vestingTimes ||
            ((fullPeriod - vestingCliffPeriod) / vestingTimes) * vestingTimes == fullPeriod - vestingCliffPeriod,
            "Incorrect vesting times"
        );
        _allPlans.push(Plan({
            fullPeriod: fullPeriod,
            vestingCliffPeriod: vestingCliffPeriod,
            vestingPeriod: TimeLine(vestingPeriod - 1),
            regularPaymentTime: vestingTimes,
            isUnvestedDelegatable: isUnvestedDelegatable
        }));
        emit PlanCreated(_allPlans.length - 1);
    }

    /**
     * @dev Allows Owner to terminate vesting of an Core holder. Performed when
     * a holder is terminated.
     *
     * Requirements:
     *
     * - Core holder must be active.
     */
    function stopVesting(address holder) external onlyOwner {
        require(
            _vestingHolders[holder].status == HolderStatus.ACTIVE,
            "Cannot stop vesting for a non active holder"
        );
        // TODO add deactivate logic!!!
        // _vestedAmount[holder] = calculateVestedAmount(holder);
        CoreEscrow(_holderToEscrow[holder]).cancelVesting(calculateVestedAmount(holder));
    }

    /**
     * @dev Allows Owner to register a holder to an Core.
     *
     * Requirements:
     *
     * - Core must already exist.
     * - The vesting amount must be less than or equal to the full allocation.
     * - The holder address must not already be included in the Core.
     */
    function connectHolderToPlan(
        address holder,
        uint planId,
        uint startVestingTime, // timestamp
        uint fullAmount,
        uint lockupAmount
    )
        external
        onlyOwner
    {
        require(_allPlans.length >= planId && planId > 0, "Core does not exist");
        require(fullAmount >= lockupAmount, "Incorrect amounts");
        // require(startVestingTime <= now, "Incorrect period starts");
        // TODO: Remove to allow both past and future vesting start date
        require(_vestingHolders[holder].status == HolderStatus.UNKNOWN, "Holder is already added");
        _vestingHolders[holder] = PlanHolder({
            status: HolderStatus.CONFIRMATION_PENDING,
            planId: planId,
            startVestingTime: startVestingTime,
            fullAmount: fullAmount,
            afterLockupAmount: lockupAmount
        });
        _holderToEscrow[holder] = _deployEscrow(holder);
    }

    /**
     * @dev Returns vesting start date of the holder's Core.
     */
    function getStartVestingTime(address holder) external view returns (uint) {
        return _vestingHolders[holder].startVestingTime;
    }

    /**
     * @dev Returns the final vesting date of the holder's Core.
     */
    function getFinishVestingTime(address holder) external view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        PlanHolder memory planHolder = _vestingHolders[holder];
        Plan memory planParams = _allPlans[planHolder.planId - 1];
        return timeHelpers.addMonths(planHolder.startVestingTime, planParams.fullPeriod);
    }

    /**
     * @dev Returns the vesting cliff period in months.
     */
    function getVestingCliffInMonth(address holder) external view returns (uint) {
        return _allPlans[_vestingHolders[holder].planId - 1].vestingCliffPeriod;
    }

    /**
     * @dev Confirms whether the holder is active in the Core.
     */
    function isActiveVestingTerm(address holder) external view returns (bool) {
        return _vestingHolders[holder].status == HolderStatus.ACTIVE;
    }

    /**
     * @dev Confirms whether the holder is approved in an Core.
     */
    function isApprovedHolder(address holder) external view returns (bool) {
        return _vestingHolders[holder].status != HolderStatus.UNKNOWN &&
            _vestingHolders[holder].status != HolderStatus.CONFIRMATION_PENDING;
    }

    /**
     * @dev Confirms whether the holder is registered in an Core.
     */
    function isHolderRegistered(address holder) external view returns (bool) {
        return _vestingHolders[holder].status != HolderStatus.UNKNOWN;
    }

    /**
     * @dev Confirms whether the holder's Core allows all un-vested tokens to be
     * delegated.
     */
    function isUnvestedDelegatableTerm(address holder) external view returns (bool) {
        return _allPlans[_vestingHolders[holder].planId - 1].isUnvestedDelegatable;
    }

    /**
     * @dev Returns the locked and unlocked (full) amount of tokens allocated to
     * the holder address in Core.
     */
    function getFullAmount(address holder) external view returns (uint) {
        return _vestingHolders[holder].fullAmount;
    }

    /**
     * @dev Returns the Core Escrow contract by holder.
     */
    function getEscrowAddress(address holder) external view returns (address) {
        return address(_holderToEscrow[holder]);
    }

    /**
     * @dev Returns the timestamp when vesting cliff ends and periodic vesting
     * begins.
     */
    function getLockupPeriodTimestamp(address holder) external view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        PlanHolder memory planHolder = _vestingHolders[holder];
        Plan memory planParams = _allPlans[planHolder.planId - 1];
        return timeHelpers.addMonths(planHolder.startVestingTime, planParams.vestingCliffPeriod);
    }

    /**
     * @dev Returns the time of the next vesting period.
     */
    function getTimeOfNextVest(address holder) external view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        uint date = now;
        PlanHolder memory planHolder = _vestingHolders[holder];
        Plan memory planParams = _allPlans[planHolder.planId - 1];
        uint lockupDate = timeHelpers.addMonths(planHolder.startVestingTime, planParams.vestingCliffPeriod);
        if (date < lockupDate) {
            return lockupDate;
        }
        uint dateTime = _getTimePointInCorrectPeriod(date, planParams.vestingPeriod);
        uint lockupTime = _getTimePointInCorrectPeriod(
            timeHelpers.addMonths(planHolder.startVestingTime, planParams.vestingCliffPeriod),
            planParams.vestingPeriod
        );
        uint finishTime = _getTimePointInCorrectPeriod(
            timeHelpers.addMonths(planHolder.startVestingTime, planParams.fullPeriod),
            planParams.vestingPeriod
        );
        uint numberOfDonePayments = dateTime.sub(lockupTime).div(planParams.regularPaymentTime);
        uint numberOfAllPayments = finishTime.sub(lockupTime).div(planParams.regularPaymentTime);
        if (numberOfAllPayments <= numberOfDonePayments + 1) {
            return timeHelpers.addMonths(
                planHolder.startVestingTime,
                planParams.fullPeriod
            );
        }
        uint nextPayment = finishTime
            .sub(
                planParams.regularPaymentTime.mul(numberOfAllPayments.sub(numberOfDonePayments + 1))
            );
        return _addMonthsAndTimePoint(lockupDate, nextPayment - lockupTime, planParams.vestingPeriod);
    }

    /**
     * @dev Returns the Core parameters.
     *
     * Requirements:
     *
     * - Core must already exist.
     */
    function getPlan(uint planId) external view returns (Plan memory) {
        require(planId > 0 && planId <= _allPlans.length, "Plan Round does not exist");
        return _allPlans[planId - 1];
    }

    /**
     * @dev Returns the Core parameters for a holder address.
     *
     * Requirements:
     *
     * - Holder address must be registered to an Core.
     */
    function getHolderParams(address holder) external view returns (PlanHolder memory) {
        require(_vestingHolders[holder].status != HolderStatus.UNKNOWN, "Plan holder is not registered");
        return _vestingHolders[holder];
    }

    /**
     * @dev Returns the locked token amount. TODO: remove, controlled by Core Escrow
     */
    function getLockedAmount(address wallet) external view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        PlanHolder memory planHolder = _vestingHolders[wallet];
        Plan memory planParams = _allPlans[planHolder.planId - 1];
        if (now < timeHelpers.addMonths(planHolder.startVestingTime, planParams.vestingCliffPeriod)) {
            return _vestingHolders[wallet].fullAmount;
        }
        return _vestingHolders[wallet].fullAmount - calculateVestedAmount(wallet);
    }
    /**
     * @dev Returns the locked token amount. TODO: remove, controlled by Core Escrow
     */
    // function getLockedAmountForDelegation(address wallet) external view returns (uint) {
    //     return _vestingHolders[wallet].fullAmount - calculateVestedAmount(wallet);
    // }

    function initialize(address contractManagerAddress) public override initializer {
        Permissions.initialize(contractManagerAddress);
        vestingManager = msg.sender;
        _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
    }

    /**
     * @dev Calculates and returns the vested token amount.
     */
    function calculateVestedAmount(address wallet) public view returns (uint vestedAmount) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        uint date = now;
        PlanHolder memory planHolder = _vestingHolders[wallet];
        Plan memory planParams = _allPlans[planHolder.planId - 1];
        vestedAmount = 0;
        if (date >= timeHelpers.addMonths(planHolder.startVestingTime, planParams.vestingCliffPeriod)) {
            vestedAmount = planHolder.afterLockupAmount;
            if (date >= timeHelpers.addMonths(planHolder.startVestingTime, planParams.fullPeriod)) {
                vestedAmount = planHolder.fullAmount;
            } else {
                uint partPayment = _getPartPayment(wallet, planHolder.fullAmount, planHolder.afterLockupAmount);
                vestedAmount = vestedAmount.add(partPayment.mul(_getNumberOfCompletedVestingEvents(wallet)));
            }
        }
    }

    /**
     * @dev Returns the number of vesting events that have completed.
     */
    function _getNumberOfCompletedVestingEvents(address wallet) internal view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        uint date = now;
        PlanHolder memory planHolder = _vestingHolders[wallet];
        Plan memory planParams = _allPlans[planHolder.planId - 1];
        if (date < timeHelpers.addMonths(planHolder.startVestingTime, planParams.vestingCliffPeriod)) {
            return 0;
        }
        uint dateTime = _getTimePointInCorrectPeriod(date, planParams.vestingPeriod);
        uint lockupTime = _getTimePointInCorrectPeriod(
            timeHelpers.addMonths(planHolder.startVestingTime, planParams.vestingCliffPeriod),
            planParams.vestingPeriod
        );
        return dateTime.sub(lockupTime).div(planParams.regularPaymentTime);
    }

    /**
     * @dev Returns the number of total vesting events.
     */
    function _getNumberOfAllVestingEvents(address wallet) internal view returns (uint) {
        ITimeHelpers timeHelpers = ITimeHelpers(contractManager.getContract("TimeHelpers"));
        PlanHolder memory planHolder = _vestingHolders[wallet];
        Plan memory planParams = _allPlans[planHolder.planId - 1];
        uint finishTime = _getTimePointInCorrectPeriod(
            timeHelpers.addMonths(planHolder.startVestingTime, planParams.fullPeriod),
            planParams.vestingPeriod
        );
        uint afterLockupTime = _getTimePointInCorrectPeriod(
            timeHelpers.addMonths(planHolder.startVestingTime, planParams.vestingCliffPeriod),
            planParams.vestingPeriod
        );
        return finishTime.sub(afterLockupTime).div(planParams.regularPaymentTime);
    }

    /**
     * @dev Returns the amount of tokens that are unlocked in each vesting
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
        return fullAmount.sub(afterLockupPeriodAmount).div(_getNumberOfAllVestingEvents(wallet));
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

    function _deployEscrow(address holder) private returns (CoreEscrow) {
        // TODO: replace with ProxyFactory when @openzeppelin/upgrades will be compatible with solidity 0.6
        IProxyFactory proxyFactory = IProxyFactory(contractManager.getContract("ProxyFactory"));
        CoreEscrow coreEscrow = CoreEscrow(contractManager.getContract("CoreEscrow"));
        // TODO: change address to ProxyAdmin when @openzeppelin/upgrades will be compatible with solidity 0.6
        IProxyAdmin proxyAdmin = IProxyAdmin(contractManager.getContract("ProxyAdmin"));

        return CoreEscrow(
            proxyFactory.deploy(
                0,
                proxyAdmin.getProxyImplementation(address(coreEscrow)),
                address(proxyAdmin),
                abi.encodeWithSelector(
                    CoreEscrow.initialize.selector,
                    address(contractManager),
                    holder
                )
            )
        );
    }
}