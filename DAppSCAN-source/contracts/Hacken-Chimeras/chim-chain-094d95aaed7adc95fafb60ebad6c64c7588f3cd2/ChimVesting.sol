// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract ChimVesting is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // `erc20TokenAddress` - erc20 contract address, tokens of which are used during vesting
    address private _erc20TokenAddress;
    // `releaseTime` - timestamp date when vesting plans started
    uint256 private _releaseTime;

    // Lock plan data structure
    struct LockPlanData {
        string name;
        uint256 maxPlanTotal;
        uint256 total;
        uint256 withdrawn;
        uint16 startPercent;
        uint32 startDelay;
        uint16 nextPercent;
        uint32 nextDelay;
    }
    // Maximum allowable percentage
    uint256 private constant _MAX_PERCENT = 10000; // 10000 equal 100%
    // Maximum allowable lock plan count
    uint256 private constant _MAX_LOCK_PLANS = 15;
    // Lock pLan ID tracker
    Counters.Counter private _lockPLanIdTracker;
    // Mapping from lock plan ID to plan data information
    mapping(uint256 => LockPlanData) private _lockPLans;

    // Address lock data structure
    struct AddressLockData {
        uint256 total;
        uint256 withdrawn;
    }
    // Mapping from address to mapping (lock pLan ID to address lock data information)
    mapping(address => mapping(uint256 => AddressLockData)) private _addressLocks;

    /**
     * @dev Emitted when `releaseTime` set.
     */
    event ReleaseTimeSet(uint256 time);
    /**
     * @dev Emitted when added new lock plan.
     */
    event LockPlanAdded(uint256 lockPlanId);
    /**
     * @dev Emitted when updated lock plan.
     */
    event LockPlanUpdated(uint256 lockPlanId);
    /**
     * @dev Emitted when token accrued to account according vesting plan.
     */
    event TokensLocked(address indexed account, uint256 lockPlanId, uint256 amount);
    /**
     * @dev Emitted when token withdrawn by account according vesting plan.
     */
    event TokensWithdrawn(address indexed account, uint256 lockPlanId, uint256 amount);

    /**
     * @dev Contract constructor. Set contract address, tokens of which are used during vesting
     *
     * Requirements:
     * - `erc20TokenAddress` cannot be the zero address.
     */
    constructor(address erc20TokenAddress_) {
        require(erc20TokenAddress_ != address(0), "ChimVesting: Invalid erc20 token address");
        _erc20TokenAddress = erc20TokenAddress_;
    }

    /**
     * @dev Returns erc20 contract address, tokens of which are used during vesting
     */
    function erc20TokenAddress() external view returns (address) {
        return _erc20TokenAddress;
    }

    /**
     * @dev Returns maximum count of vesting lock plans
     */
    function maxLockPlans() external pure returns (uint256) {
        return _MAX_LOCK_PLANS;
    }

    /**
     * @dev Returns current count of vesting lock plans
     */
    function getLockPlanCount() external view returns (uint256) {
        return Counters.current(_lockPLanIdTracker);
    }

    /**
     * @dev Returns vesting lock plan information for `lockPlanId`.
     */
    function getLockPlan(uint256 lockPlanId_)
        external
        view
        returns (
            string memory name,
            uint256 maxPlanTotal,
            uint256 total,
            uint256 locked,
            uint256 withdrawn,
            uint16 startPercent,
            uint32 startDelay,
            uint16 nextPercent,
            uint32 nextDelay
        )
    {
        LockPlanData storage lockPlan = _lockPLans[lockPlanId_];
        return (
            lockPlan.name,
            lockPlan.maxPlanTotal,
            lockPlan.total,
            lockPlan.total.sub(lockPlan.withdrawn),
            lockPlan.withdrawn,
            lockPlan.startPercent,
            lockPlan.startDelay,
            lockPlan.nextPercent,
            lockPlan.nextDelay
        );
    }

    /**
     * @dev For `account`, it returns the current plan (with `lockPlanId`) information about locks.
     */
    function getPlanBalanceOf(
        address account_,
        uint256 lockPlanId_
    )
        external
        view
        returns (
            uint256 total,
            uint256 locked,
            uint256 withdrawn
        )
    {
        AddressLockData storage addressLockData = _addressLocks[account_][lockPlanId_];
        return (
            addressLockData.total,
            addressLockData.total.sub(addressLockData.withdrawn),
            addressLockData.withdrawn
        );
    }

    /**
     * @dev For `account`, it returns all plans total information about locks.
     */
    function getTotalBalanceOf(address account_)
        external
        view
        returns (
            uint256 total,
            uint256 locked,
            uint256 withdrawn
        )
    {
        for (uint256 i = 1; i <= Counters.current(_lockPLanIdTracker); i++) {
            AddressLockData storage addressLockData = _addressLocks[account_][i];
            total = total.add(addressLockData.total);
            withdrawn = withdrawn.add(addressLockData.withdrawn);
        }
        return (
            total,
            total.sub(withdrawn),
            withdrawn
        );
    }

    /**
     * @dev Returns timestamp date when vesting plans started. If date is 0 - vesting has not started yet.
     */
    function releaseTime() external view returns (uint256) {
        return _releaseTime;
    }

    /**
     * @dev Returns vesting general statistics data for all accounts.
     */
    function stats()
        external
        view
        returns (
            uint256 totalBalance,
            uint256 maxPlansTotal,
            uint256 total,
            uint256 totalLocked,
            uint256 totalWithdrawn
        )
    {
        totalBalance = IERC20(_erc20TokenAddress).balanceOf(address(this));
        for (uint256 i = 1; i <= Counters.current(_lockPLanIdTracker); i++) {
            LockPlanData storage lockPlan = _lockPLans[i];
            maxPlansTotal = maxPlansTotal.add(lockPlan.maxPlanTotal);
            total = total.add(lockPlan.total);
            totalWithdrawn = totalWithdrawn.add(lockPlan.withdrawn);
        }
        return (
            totalBalance,
            maxPlansTotal,
            total,
            total.sub(totalWithdrawn),
            totalWithdrawn
        );
    }

    /**
     * @dev For `account`, checks locks for plan (with `lockPlanId`), receive `pendingUnlock` - how much `account` can withdraw right now
     */
    function checkLocks(
        address account_,
        uint256 lockPlanId_
    )
        public
        view
        returns (
            uint256 afterReleaseTime,
            uint256 unlockPercents,
            uint256 nextUnlockTime,
            uint256 total,
            uint256 totalUnlock,
            uint256 withdrawn,
            uint256 pendingUnlock
        )
    {
        if (_releaseTime == 0 || _releaseTime > block.timestamp || lockPlanId_ == 0 || lockPlanId_ > Counters.current(_lockPLanIdTracker)) {
            return (0, 0, 0, 0, 0, 0, 0);
        }
//    SWC-116-Block values as a proxy for time: L242
        LockPlanData storage lockPlan = _lockPLans[lockPlanId_];
        afterReleaseTime = block.timestamp.sub(_releaseTime);
        unlockPercents = lockPlan.startPercent;
        for (nextUnlockTime = lockPlan.startDelay; lockPlan.nextPercent > 0 && lockPlan.nextDelay > 0 && nextUnlockTime <= afterReleaseTime && unlockPercents < _MAX_PERCENT; nextUnlockTime = nextUnlockTime.add(lockPlan.nextDelay)) {
            unlockPercents = unlockPercents.add(lockPlan.nextPercent);
        }
        if (unlockPercents >= _MAX_PERCENT) {
            unlockPercents = _MAX_PERCENT;
            nextUnlockTime = 0;
        }

        AddressLockData storage addressLockData = _addressLocks[account_][lockPlanId_];
        total = addressLockData.total;
        totalUnlock = total.mul(unlockPercents).div(_MAX_PERCENT);
        withdrawn = addressLockData.withdrawn;
        if (totalUnlock > withdrawn) {
            pendingUnlock = totalUnlock.sub(withdrawn);
        }

        return (
            afterReleaseTime,
            unlockPercents,
            nextUnlockTime,
            total,
            totalUnlock,
            withdrawn,
            pendingUnlock
        );
    }

    /**
     * @dev MsgSender() withdraw all available own funds by under plan (with `lockPlanId`)
     *
     * Requirements:
     * - `releaseTime` must be set,
     * - `lockPlanId` must exist.
     */
    function withdraw(uint256 lockPlanId_) external nonReentrant {
        require(_releaseTime != 0, "ChimVesting: The release time not set");
        require(lockPlanId_ > 0 && lockPlanId_ <= Counters.current(_lockPLanIdTracker), "ChimVesting: LockPlanId not exist");

        (, , , , , , uint256 pendingUnlock) = checkLocks(_msgSender(), lockPlanId_);

        if (pendingUnlock == 0) {
            return;
        }

        LockPlanData storage lockPlan = _lockPLans[lockPlanId_];
        lockPlan.withdrawn = lockPlan.withdrawn.add(pendingUnlock);

        AddressLockData storage addressLockData = _addressLocks[_msgSender()][lockPlanId_];
        addressLockData.withdrawn = addressLockData.withdrawn.add(pendingUnlock);

        IERC20(_erc20TokenAddress).safeTransfer(_msgSender(), pendingUnlock);

        emit TokensWithdrawn(_msgSender(), lockPlanId_, pendingUnlock);
    }

    /**
     * @dev Set vesting `releaseTime`
     *
     * Requirements:
     * - must be called by owner account,
     * - `releaseTime` should not be set yet.
     */
    function setReleaseTime(uint256 time_) external onlyOwner {
        require(_releaseTime == 0, "ChimVesting: The release time can only be set once");

        _releaseTime = time_;

        emit ReleaseTimeSet(time_);
    }

    /**
     * @dev Add new vesting lock plan
     *
     * Requirements:
     * - must be called by owner account,
     * - current count of vesting plans is less than `MAX_LOCK_PLANS` limit,
     * - `name` must not be an empty string,
     * - `maxPlanTotal` must be greater than 0,
     * - `startPercent` must be between [0, 10000],
     * - `nextPercent_` must be between [0, 10000],
     * - `startPercent` should be 10000 or nextPercent and nextDelay should be greater than 0.
     */
    function addLockPlan(
        string memory name_,
        uint256 maxPlanTotal_,
        uint16 startPercent_,
        uint32 startDelay_,
        uint16 nextPercent_,
        uint32 nextDelay_
    )
        external
        onlyOwner
    {
        require(Counters.current(_lockPLanIdTracker) < _MAX_LOCK_PLANS, "ChimVesting: Max lock plans limit reached");
        require(bytes(name_).length != 0, "ChimVesting: Invalid name");
        require(maxPlanTotal_ != 0, "ChimVesting: Invalid max plan total");
        require(startPercent_ <= _MAX_PERCENT, "ChimVesting: Invalid start percent");
        require(nextPercent_ <= _MAX_PERCENT, "ChimVesting: Invalid next percent");
        require(startPercent_ == _MAX_PERCENT || (nextPercent_ > 0 && nextDelay_ > 0), "ChimVesting: Invalid plan params");

        Counters.increment(_lockPLanIdTracker);
        LockPlanData storage lockPlan = _lockPLans[Counters.current(_lockPLanIdTracker)];
        lockPlan.name = name_;
        lockPlan.maxPlanTotal = maxPlanTotal_;
        lockPlan.startPercent = startPercent_;
        lockPlan.startDelay = startDelay_;
        lockPlan.nextPercent = nextPercent_;
        lockPlan.nextDelay = nextDelay_;

        emit LockPlanAdded(Counters.current(_lockPLanIdTracker));
    }

    /**
     * @dev Update vesting lock plan
     *
     * Requirements:
     * - must be called by owner account,
     * - `lockPlanId` must exist,
     * - `name` must not be an empty string,
     * - `startPercent` must be between [0, 10000],
     * - `nextPercent_` must be between [0, 10000],
     * - `startPercent` should be 10000 or nextPercent and nextDelay should be greater than 0.
     */
    function updateLockPlan(
        uint256 lockPlanId_,
        string memory name_,
        uint16 startPercent_,
        uint32 startDelay_,
        uint16 nextPercent_,
        uint32 nextDelay_
    )
        external
        onlyOwner
    {
        require(lockPlanId_ > 0 && lockPlanId_ <= Counters.current(_lockPLanIdTracker), "ChimVesting: LockPlanId not exist");
        require(bytes(name_).length != 0, "ChimVesting: Invalid name");
        require(startPercent_ <= _MAX_PERCENT, "ChimVesting: Invalid start percent");
        require(nextPercent_ <= _MAX_PERCENT, "ChimVesting: Invalid next percent");
        require(startPercent_ == _MAX_PERCENT || (nextPercent_ > 0 && nextDelay_ > 0), "ChimVesting: Invalid plan params");

        LockPlanData storage lockPlan = _lockPLans[lockPlanId_];
        lockPlan.name = name_;
        lockPlan.startPercent = startPercent_;
        lockPlan.startDelay = startDelay_;
        lockPlan.nextPercent = nextPercent_;
        lockPlan.nextDelay = nextDelay_;

        emit LockPlanUpdated(lockPlanId_);
    }

    /**
     * @dev Locks (accrued) `amount` tokens to `account` according vesting plan (with `lockPlanId`).
     *
     * Requirements:
     * - must be called by owner account,
     * - `account` cannot be the zero address,
     * - `lockPlanId` must exist,
     * - not exceeding the `maxPlanTotal` limit according to plan.
     */
    function lockTokens(
        address account_,
        uint256 amount_,
        uint256 lockPlanId_
    )
        external
        onlyOwner
        nonReentrant
    {
        require(account_ != address(0), "ChimVesting: Invalid address");
        require(lockPlanId_ > 0 && lockPlanId_ <= Counters.current(_lockPLanIdTracker), "ChimVesting: LockPlanId not exist");

        LockPlanData storage lockPlan = _lockPLans[lockPlanId_];
        lockPlan.total = lockPlan.total.add(amount_);
        require(lockPlan.maxPlanTotal >= lockPlan.total, "ChimVesting: Max plan total limit reached");

        AddressLockData storage addressLockData = _addressLocks[account_][lockPlanId_];
        addressLockData.total = addressLockData.total.add(amount_);

        emit TokensLocked(account_, lockPlanId_, amount_);
    }
}
