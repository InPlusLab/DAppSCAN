// SPDX-License-Identifier: MIT
// SWC-103-Floating Pragma: L3
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IStaking.sol";

contract Staking is AccessControl, ReentrancyGuard, IStaking {
    using SafeERC20 for IERC20;

    bytes32 public constant FABRIC = keccak256("FABRIC");
    bytes32 public constant PRESALE = keccak256("PRESALE");

    uint256 public constant FEE = 25;
    uint256 public constant YEAR = 60 * 60 * 24 * 365;

    IERC20 public immutable QUACK;

    uint256 public poolStartTime;
    uint256 public poolEndTime;
    uint256 public totalStaked;
    uint256 public feesCollected;

// SWC-135-Code With No Effects: L27
    address public relockOw;

    uint24 private constant DAY = 1 days;
    uint256 private constant BASE = 100;

    uint256[9] private _levels = [
        100000000000 * (10**9),
        500000000000 * (10**9),
        2000000000000 * (10**9),
        5500000000000 * (10**9),
        12000000000000 * (10**9),
        19000000000000 * (10**9),
        26000000000000 * (10**9),
        70000000000000 * (10**9),
        150000000000000 * (10**9)
    ];
    uint256[4] private _lockType = [
        7 days,
        14 days,
        30 days,
        90 days
    ];
    uint256[4] private _apr = [0, 8, 13, 28];

    mapping(address => UserInfo) public stakeInfo;
    mapping(address => uint256) public emergencyReward;

    struct UserInfo {
        uint256 level;
        uint256 totalStakedForUser;
        uint256[4] rewardTaken;
        uint256[4] sumInLock;
        uint256[4] enteredAt;
        uint256[3] reLocks;
    }

    modifier startedAndNotEnded() {
        require(
            poolStartTime > 0 && poolEndTime == 0,
            "Pool not yet started or already ended"
        );
        _;
    }

    event ReLock(address user, uint256 timestamp);

    constructor(address _quack, address _owner) {
        require(_quack != address(0), "Staking: address(0)");
        QUACK = IERC20(_quack);
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function stakeForUser(address user, uint256 lockUp)
        external
        view
        returns (
            uint256 level,
            uint256 totalStakedForUser,
            bool first_lock,
            bool second_lock,
            bool third_lock,
            bool fourth_lock,
            uint256 amountLock,
            uint256 rewardTaken,
            uint256 enteredAt
        )
    {
        UserInfo storage stake = stakeInfo[user];
        level = stake.level;
        totalStakedForUser = stake.totalStakedForUser;
        first_lock = (stake.sumInLock[0] > 0);
        second_lock = (stake.sumInLock[1] > 0);
        third_lock = (stake.sumInLock[2] > 0);
        fourth_lock = (stake.sumInLock[3] > 0);
        amountLock = stake.sumInLock[lockUp];
        rewardTaken = stake.rewardTaken[lockUp];
        enteredAt = stake.enteredAt[lockUp];
    }

    function addFabric(address fabric) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setupRole(FABRIC, fabric);
    }

    function addPresale(address presale) external {
        address sender = _msgSender();
        require(hasRole(FABRIC, sender) || hasRole(DEFAULT_ADMIN_ROLE, sender));
        _setupRole(PRESALE, presale);
    }

    function getFees() external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        QUACK.safeTransfer(_msgSender(), feesCollected);
        delete feesCollected;
    }

    // SWC-116-Block values as a proxy for time: L125
    function startPool() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(poolStartTime == 0, "Already started");
        poolStartTime = block.timestamp;
    }

    function endPool()
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        startedAndNotEnded
    {
        // SWC-116-Block values as a proxy for time: L134
        poolEndTime = block.timestamp;
        uint256 toTransfer = QUACK.balanceOf(address(this)) -
            (totalStaked + feesCollected);
        if (toTransfer > 0) QUACK.safeTransfer(_msgSender(), toTransfer);
    }

    function deposit(uint256 amount, uint256 lockUp)
        external
        startedAndNotEnded
        nonReentrant
    {
        require(amount > 0, "Cannot stake zero");
        require(lockUp < 4, "Incorrect lockUp");

        address user = _msgSender();

        UserInfo storage stake = stakeInfo[user];

        uint256 toTransfer = _allRewars(user);

        if (toTransfer > 0) {
            require(
                QUACK.balanceOf(address(this)) -
                    (totalStaked + feesCollected) >=
                    toTransfer,
                "Not enough token for reward"
            );
            QUACK.safeTransfer(user, toTransfer);
        }
        QUACK.safeTransferFrom(user, address(this), amount);

        stake.totalStakedForUser += amount;
        totalStaked += amount;

        _updateLevel(user);

        if (lockUp < 2)
            require(stake.level <= 3 + (3 * lockUp), "Incorrect level");
        stake.sumInLock[lockUp] += amount;
        stake.rewardTaken[lockUp] = 0;
        if (lockUp < 3) stake.reLocks[lockUp] = 0;
        // SWC-116-Block values as a proxy for time: L176
        stake.enteredAt[lockUp] = block.timestamp;
    }

    function emergencyWithdraw(bool reward) external nonReentrant {
        address user = _msgSender();
        uint256 toTransfer;
        if (reward) {
            toTransfer = emergencyReward[user];
            require(toTransfer > 0, "You don't have rewards");
            delete emergencyReward[user];
            require(
                QUACK.balanceOf(address(this)) -
                    (totalStaked + feesCollected) >=
                    toTransfer,
                "Not enough token for reward"
            );
            QUACK.safeTransfer(user, toTransfer);
        } else {
            UserInfo storage stake = stakeInfo[user];
            uint256 rew;
            for (uint256 i; i < 4; i += 1) {
                if (stake.sumInLock[i] > 0) {
                    rew += nextReward(user, i);
                    toTransfer += _calcFee(user, i, stake.sumInLock[i]);
                    totalStaked -= stake.sumInLock[i];
                    stake.sumInLock[i] = 0;
                }
            }
            emergencyReward[user] = rew;

            delete stakeInfo[user];
            require(toTransfer > 0, "You don't stake any tokens");
            require(
                QUACK.balanceOf(address(this)) -
                    (totalStaked + feesCollected) >=
                    toTransfer,
                "Not enough token for withdraw"
            );
            QUACK.safeTransfer(user, toTransfer);
        }
    }

    function withdraw(uint256 amount, uint256 lockUp) external nonReentrant {
        require(lockUp < 4, "Incorrect lockUp");
        address user = _msgSender();
        UserInfo storage stake = stakeInfo[user];
        require(
            stake.sumInLock[lockUp] >= amount,
            "Cannot withdraw this much for such lock"
        );
        uint256 toTransfer = _allRewars(user);

        if (amount > 0) {
            toTransfer += _calcFee(user, lockUp, amount);
            stake.totalStakedForUser -= amount;
            stake.sumInLock[lockUp] -= amount;
            totalStaked -= amount;

            if (stake.totalStakedForUser == 0) {
                delete stakeInfo[user];
            } else if (stake.sumInLock[lockUp] == 0) {
                delete stake.rewardTaken[lockUp];
                if (lockUp < 3) delete stake.reLocks[lockUp];
                delete stake.sumInLock[lockUp];
                delete stake.enteredAt[lockUp];
            } else {
                stake.rewardTaken[lockUp] =
                    (stakeInfo[user].sumInLock[lockUp] *
                        _apr[lockUp] *
                        (_timestamp() - stakeInfo[user].enteredAt[lockUp])) /
                    (BASE * YEAR);
            }
            _updateLevel(user);
        }

        if (toTransfer > 0) {
            require(
                QUACK.balanceOf(address(this)) -
                    (totalStaked + feesCollected) >=
                    toTransfer,
                "Not enough token for reward"
            );
            QUACK.safeTransfer(user, toTransfer);
        }
    }

    function addReLock(address user) external onlyRole(PRESALE) {
        UserInfo storage stake = stakeInfo[user];
        for (uint256 i; i < 3; i += 1) {
            if (stake.sumInLock[i] > 0) stake.reLocks[i] += 5 * DAY;
        }
        emit ReLock(user, block.timestamp);
    }

    function nextReward(address user, uint256 lockUp)
        public
        view
        returns (uint256)
    {
        return
            (stakeInfo[user].sumInLock[lockUp] *
                _apr[lockUp] *
                (_timestamp() - stakeInfo[user].enteredAt[lockUp])) /
            (BASE * YEAR) -
            stakeInfo[user].rewardTaken[lockUp];
    }

    function _allRewars(address user) private returns (uint256 toTransfer) {
        UserInfo storage stake = stakeInfo[user];
        if (stake.totalStakedForUser > 0) {
            uint256 rew;
            for (uint256 i; i < 4; i += 1) {
                if (stake.sumInLock[i] > 0) {
                    rew = nextReward(user, i);
                    stake.rewardTaken[i] += rew;
                    toTransfer += rew;
                }
            }
        }
    }

    function _calcFee(
        address user,
        uint256 lockUp,
        uint256 amount
    ) private returns (uint256 toTransfer) {
        UserInfo storage stake = stakeInfo[user];
        if (
            (lockUp < 3 &&
                stake.enteredAt[lockUp] +
                    _lockType[lockUp] +
                    stake.reLocks[lockUp] >
                block.timestamp) ||
            (lockUp == 3 &&
                stake.enteredAt[lockUp] + _lockType[lockUp] > block.timestamp)
        ) {
            uint256 fee = (amount * FEE) / BASE;
            feesCollected += fee;
            toTransfer += (amount - fee);
        } else {
            toTransfer += amount;
        }
    }

    function _timestamp() private view returns (uint256) {
        if (poolEndTime == 0) return block.timestamp;
        else return poolEndTime;
    }

    function _updateLevel(address user) private {
        UserInfo storage stake = stakeInfo[user];

        if (stake.totalStakedForUser >= _levels[8]) {
            stake.level = 9;
        } else if (stake.totalStakedForUser < _levels[0]) {
            stake.level = 0;
        } else {
            for (uint256 i; i < 8; i += 1) {
                if (
                    stake.totalStakedForUser >= _levels[i] &&
                    stake.totalStakedForUser < _levels[i + 1]
                ) {
                    stake.level = i + 1;
                    return;
                }
            }
        }
    }
}