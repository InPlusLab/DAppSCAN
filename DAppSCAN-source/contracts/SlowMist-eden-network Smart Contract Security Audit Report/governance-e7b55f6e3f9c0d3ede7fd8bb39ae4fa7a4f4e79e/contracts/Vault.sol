// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IERC20Permit.sol";
import "./interfaces/ILockManager.sol";
import "./lib/SafeERC20.sol";

/**
 * @title Vault
 * @dev Contract for locking up tokens for set periods of time 
 * + optionally providing locked tokens with voting power
 */
contract Vault {
    using SafeERC20 for IERC20Permit;

    /// @notice lockManager contract
    ILockManager public immutable lockManager;

    /// @notice Lock definition
    struct Lock {
        address token;
        address receiver;
        uint48 startTime;
        uint16 vestingDurationInDays;
        uint16 cliffDurationInDays;
        uint256 amount;
        uint256 amountClaimed;
        uint256 votingPower;
    }

    /// @notice Lock balance definition
    struct LockBalance {
        uint256 id;
        uint256 claimableAmount;
        Lock lock;
    }

    /// @notice Token balance definition
    struct TokenBalance {
        uint256 totalAmount;
        uint256 claimableAmount;
        uint256 claimedAmount;
        uint256 votingPower;
    }

    /// @dev Used to translate lock periods specified in days to seconds
    uint256 constant internal SECONDS_PER_DAY = 86400;
    
    /// @notice Mapping of lock id > token locks
    mapping (uint256 => Lock) public tokenLocks;

    /// @notice Mapping of address to lock id
    mapping (address => uint256[]) public lockIds;

    /// @notice Number of locks
    uint256 public numLocks;

    /// @notice Event emitted when a new lock is created
    event LockCreated(address indexed token, address indexed locker, address indexed receiver, uint256 lockId, uint256 amount, uint48 startTime, uint16 durationInDays, uint16 cliffInDays, uint256 votingPower);
    
    /// @notice Event emitted when tokens are claimed by a receiver from an unlocked balance
    event UnlockedTokensClaimed(address indexed receiver, address indexed token, uint256 indexed lockId, uint256 amountClaimed, uint256 votingPowerRemoved);

    /// @notice Event emitted when lock duration extended
    event LockExtended(uint256 indexed lockId, uint16 indexed oldDuration, uint16 indexed newDuration, uint16 oldCliff, uint16 newCliff, uint48 startTime);

    /**
     * @notice Create a new Vault contract
     * @param _lockManager LockManager contract address
     */
    constructor(address _lockManager) {
        lockManager = ILockManager(_lockManager);
    }

    /**
     * @notice Lock tokens, optionally providing voting power
     * @param locker The account that is locking tokens
     * @param receiver The account that will be able to retrieve unlocked tokens
     * @param startTime The unix timestamp when the lock period will start
     * @param amount The amount of tokens being locked
     * @param vestingDurationInDays The vesting period in days
     * @param cliffDurationInDays The cliff duration in days
     * @param grantVotingPower if true, give user voting power from tokens
     */
    function lockTokens(
        address token,
        address locker,
        address receiver,
        uint48 startTime,
        uint256 amount,
        uint16 vestingDurationInDays,
        uint16 cliffDurationInDays,
        bool grantVotingPower
    )
        external
    {
        require(vestingDurationInDays > 0, "Vault::lockTokens: vesting duration must be > 0");
        require(vestingDurationInDays <= 25*365, "Vault::lockTokens: vesting duration more than 25 years");
        require(vestingDurationInDays >= cliffDurationInDays, "Vault::lockTokens: vesting duration < cliff");
        require(amount > 0, "Vault::lockTokens: amount not > 0");
        _lockTokens(token, locker, receiver, startTime, amount, vestingDurationInDays, cliffDurationInDays, grantVotingPower);
    }

    /**
     * @notice Lock tokens, using permit for approval
     * @dev It is up to the frontend developer to ensure the token implements permit - otherwise this will fail
     * @param token Address of token to lock
     * @param locker The account that is locking tokens
     * @param receiver The account that will be able to retrieve unlocked tokens
     * @param startTime The unix timestamp when the lock period will start
     * @param amount The amount of tokens being locked
     * @param vestingDurationInDays The lock period in days
     * @param cliffDurationInDays The lock cliff duration in days
     * @param grantVotingPower if true, give user voting power from tokens
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function lockTokensWithPermit(
        address token,
        address locker,
        address receiver,
        uint48 startTime,
        uint256 amount,
        uint16 vestingDurationInDays,
        uint16 cliffDurationInDays,
        bool grantVotingPower,
        uint256 deadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) 
        external
    {
        require(vestingDurationInDays > 0, "Vault::lockTokensWithPermit: vesting duration must be > 0");
        require(vestingDurationInDays <= 25*365, "Vault::lockTokensWithPermit: vesting duration more than 25 years");
        require(vestingDurationInDays >= cliffDurationInDays, "Vault::lockTokensWithPermit: duration < cliff");
        require(amount > 0, "Vault::lockTokensWithPermit: amount not > 0");

        // Set approval using permit signature
        IERC20Permit(token).permit(locker, address(this), amount, deadline, v, r, s);
        _lockTokens(token, locker, receiver, startTime, amount, vestingDurationInDays, cliffDurationInDays, grantVotingPower);
    }

    /**
     * @notice Get all active token lock ids
     * @return the lock ids
     */
    function allActiveLockIds() external view returns(uint256[] memory){
        uint256 activeCount;

        // Get number of active locks
        for (uint256 i; i < numLocks; i++) {
            Lock memory lock = tokenLocks[i];
            if(lock.amount != lock.amountClaimed) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        uint256[] memory result = new uint256[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < numLocks; i++) {
            Lock memory lock = tokenLocks[i];
            if(lock.amount != lock.amountClaimed) {
                result[j] = i;
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get all active token locks
     * @return the locks
     */
    function allActiveLocks() external view returns(Lock[] memory){
        uint256 activeCount;

        // Get number of active locks
        for (uint256 i; i < numLocks; i++) {
            Lock memory lock = tokenLocks[i];
            if(lock.amount != lock.amountClaimed) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        Lock[] memory result = new Lock[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < numLocks; i++) {
            Lock memory lock = tokenLocks[i];
            if(lock.amount != lock.amountClaimed) {
                result[j] = lock;
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get all active token lock balances
     * @return the active lock balances
     */
    function allActiveLockBalances() external view returns(LockBalance[] memory){
        uint256 activeCount;

        // Get number of active locks
        for (uint256 i; i < numLocks; i++) {
            Lock memory lock = tokenLocks[i];
            if(lock.amount != lock.amountClaimed) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        LockBalance[] memory result = new LockBalance[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < numLocks; i++) {
            Lock memory lock = tokenLocks[i];
            if(lock.amount != lock.amountClaimed) {
                result[j] = lockBalance(i);
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get all active token lock ids for receiver
     * @param receiver The address that has locked balances
     * @return the active lock ids
     */
    function activeLockIds(address receiver) external view returns(uint256[] memory){
        uint256 activeCount;
        uint256[] memory receiverLockIds = lockIds[receiver];

        // Get number of active locks
        for (uint256 i; i < receiverLockIds.length; i++) {
            Lock memory lock = tokenLocks[receiverLockIds[i]];
            if(lock.amount != lock.amountClaimed) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        uint256[] memory result = new uint256[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < receiverLockIds.length; i++) {
            Lock memory lock = tokenLocks[receiverLockIds[i]];
            if(lock.amount != lock.amountClaimed) {
                result[j] = receiverLockIds[i];
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get all token locks for receiver
     * @param receiver The address that has locked balances
     * @return the locks
     */
    function allLocks(address receiver) external view returns(Lock[] memory){
        uint256[] memory allLockIds = lockIds[receiver];
        Lock[] memory result = new Lock[](allLockIds.length);
        for (uint256 i; i < allLockIds.length; i++) {
            result[i] = tokenLocks[allLockIds[i]];
        }
        return result;
    }

    /**
     * @notice Get all active token locks for receiver
     * @param receiver The address that has locked balances
     * @return the locks
     */
    function activeLocks(address receiver) external view returns(Lock[] memory){
        uint256 activeCount;
        uint256[] memory receiverLockIds = lockIds[receiver];

        // Get number of active locks
        for (uint256 i; i < receiverLockIds.length; i++) {
            Lock memory lock = tokenLocks[receiverLockIds[i]];
            if(lock.amount != lock.amountClaimed) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        Lock[] memory result = new Lock[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < receiverLockIds.length; i++) {
            Lock memory lock = tokenLocks[receiverLockIds[i]];
            if(lock.amount != lock.amountClaimed) {
                result[j] = tokenLocks[receiverLockIds[i]];
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get all active token lock balances for receiver
     * @param receiver The address that has locked balances
     * @return the active lock balances
     */
    function activeLockBalances(address receiver) external view returns(LockBalance[] memory){
        uint256 activeCount;
        uint256[] memory receiverLockIds = lockIds[receiver];

        // Get number of active locks
        for (uint256 i; i < receiverLockIds.length; i++) {
            Lock memory lock = tokenLocks[receiverLockIds[i]];
            if(lock.amount != lock.amountClaimed) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        LockBalance[] memory result = new LockBalance[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < receiverLockIds.length; i++) {
            Lock memory lock = tokenLocks[receiverLockIds[i]];
            if(lock.amount != lock.amountClaimed) {
                result[j] = lockBalance(receiverLockIds[i]);
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get total token balance
     * @param token The token to check
     * @return balance the total active balance of `token`
     */
    function totalTokenBalance(address token) external view returns(TokenBalance memory balance){
        for (uint256 i; i < numLocks; i++) {
            Lock memory tokenLock = tokenLocks[i];
            if(tokenLock.token == token && tokenLock.amount != tokenLock.amountClaimed){
                balance.totalAmount = balance.totalAmount + tokenLock.amount;
                balance.votingPower = balance.votingPower + tokenLock.votingPower;
                if(block.timestamp > tokenLock.startTime) {
                    balance.claimedAmount = balance.claimedAmount + tokenLock.amountClaimed;

                    uint256 elapsedTime = block.timestamp - tokenLock.startTime;
                    uint256 elapsedDays = elapsedTime / SECONDS_PER_DAY;

                    if (
                        elapsedDays >= tokenLock.cliffDurationInDays
                    ) {
                        if (elapsedDays >= tokenLock.vestingDurationInDays) {
                            balance.claimableAmount = balance.claimableAmount + tokenLock.amount - tokenLock.amountClaimed;
                        } else {
                            uint256 vestingDurationInSecs = uint256(tokenLock.vestingDurationInDays) * SECONDS_PER_DAY;
                            uint256 vestingAmountPerSec = tokenLock.amount / vestingDurationInSecs;
                            uint256 amountVested = vestingAmountPerSec * elapsedTime;
                            balance.claimableAmount = balance.claimableAmount + amountVested - tokenLock.amountClaimed;
                        }
                    }
                }
            }
        }
    }

    /**
     * @notice Get token balance of receiver
     * @param token The token to check
     * @param receiver The address that has unlocked balances
     * @return balance the total active balance of `token` for `receiver`
     */
    function tokenBalance(address token, address receiver) external view returns(TokenBalance memory balance){
        uint256[] memory receiverLockIds = lockIds[receiver];
        for (uint256 i; i < receiverLockIds.length; i++) {
            Lock memory receiverLock = tokenLocks[receiverLockIds[i]];
            if(receiverLock.token == token && receiverLock.amount != receiverLock.amountClaimed){
                balance.totalAmount = balance.totalAmount + receiverLock.amount;
                balance.votingPower = balance.votingPower + receiverLock.votingPower;
                if(block.timestamp > receiverLock.startTime) {
                    balance.claimedAmount = balance.claimedAmount + receiverLock.amountClaimed;

                    uint256 elapsedTime = block.timestamp - receiverLock.startTime;
                    uint256 elapsedDays = elapsedTime / SECONDS_PER_DAY;

                    if (
                        elapsedDays >= receiverLock.cliffDurationInDays
                    ) {
                        if (elapsedDays >= receiverLock.vestingDurationInDays) {
                            balance.claimableAmount = balance.claimableAmount + receiverLock.amount - receiverLock.amountClaimed;
                        } else {
                            uint256 vestingDurationInSecs = uint256(receiverLock.vestingDurationInDays) * SECONDS_PER_DAY;
                            uint256 vestingAmountPerSec = receiverLock.amount / vestingDurationInSecs;
                            uint256 amountVested = vestingAmountPerSec * elapsedTime;
                            balance.claimableAmount = balance.claimableAmount + amountVested - receiverLock.amountClaimed;
                        }
                    }
                }
            }
        }
    }

    /**
     * @notice Get lock balance for a given lock id
     * @param lockId The lock ID
     * @return balance the lock balance
     */
    function lockBalance(uint256 lockId) public view returns (LockBalance memory balance) {
        balance.id = lockId;
        balance.claimableAmount = claimableBalance(lockId);
        balance.lock = tokenLocks[lockId];
    }

    /**
     * @notice Get claimable balance for a given lock id
     * @dev Returns 0 if cliff duration has not ended
     * @param lockId The lock ID
     * @return The amount that can be claimed
     */
    function claimableBalance(uint256 lockId) public view returns (uint256) {
        Lock storage lock = tokenLocks[lockId];

        // For locks created with a future start date, that hasn't been reached, return 0
        if (block.timestamp < lock.startTime) {
            return 0;
        }

        uint256 elapsedTime = block.timestamp - lock.startTime;
        uint256 elapsedDays = elapsedTime / SECONDS_PER_DAY;
        
        if (elapsedDays < lock.cliffDurationInDays) {
            return 0;
        } 
        
        if (elapsedDays >= lock.vestingDurationInDays) {
            return lock.amount - lock.amountClaimed;
        } else {
            uint256 vestingDurationInSecs = uint256(lock.vestingDurationInDays) * SECONDS_PER_DAY;
            uint256 vestingAmountPerSec = lock.amount / vestingDurationInSecs;
            uint256 amountVested = vestingAmountPerSec * elapsedTime;
            return amountVested - lock.amountClaimed;
        }
    }

    /**
     * @notice Allows receiver to claim all of their unlocked tokens for a set of locks
     * @dev Errors if no tokens are claimable
     * @dev It is advised receivers check they are entitled to claim via `claimableBalance` before calling this
     * @param locks The lock ids for unlocked token balances
     */
    function claimAllUnlockedTokens(uint256[] memory locks) external {
        for (uint i = 0; i < locks.length; i++) {
            uint256 claimableAmount = claimableBalance(locks[i]);
            require(claimableAmount > 0, "Vault::claimAllUnlockedTokens: claimableAmount is 0");
            _claimTokens(locks[i], claimableAmount);
        }
    }

    /**
     * @notice Allows receiver to claim a portion of their unlocked tokens for a given lock
     * @dev Errors if token amounts provided are > claimable amounts
     * @dev It is advised receivers check they are entitled to claim via `claimableBalance` before calling this
     * @param locks The lock ids for unlocked token balances
     * @param amounts The amount of each unlocked token to claim
     */
    function claimUnlockedTokenAmounts(uint256[] memory locks, uint256[] memory amounts) external {
        require(locks.length == amounts.length, "Vault::claimUnlockedTokenAmounts: arrays must be same length");
        for (uint i = 0; i < locks.length; i++) {
            uint256 claimableAmount = claimableBalance(locks[i]);
            require(claimableAmount >= amounts[i], "Vault::claimUnlockedTokenAmounts: claimableAmount < amount");
            _claimTokens(locks[i], amounts[i]);
        }
    }

    /**
     * @notice Allows receiver extend lock periods for a given lock
     * @param lockId The lock id for a locked token balance
     * @param vestingDaysToAdd The number of days to add to vesting duration
     * @param cliffDaysToAdd The number of days to add to cliff duration
     */
    function extendLock(uint256 lockId, uint16 vestingDaysToAdd, uint16 cliffDaysToAdd) external {
        Lock storage lock = tokenLocks[lockId];
        require(msg.sender == lock.receiver, "Vault::extendLock: msg.sender must be receiver");
        uint16 oldVestingDuration = lock.vestingDurationInDays;
        uint16 newVestingDuration = _add16(oldVestingDuration, vestingDaysToAdd, "Vault::extendLock: vesting max days exceeded");
        uint16 oldCliffDuration = lock.cliffDurationInDays;
        uint16 newCliffDuration = _add16(oldCliffDuration, cliffDaysToAdd, "Vault::extendLock: cliff max days exceeded");
        require(newCliffDuration <= 10*365, "Vault::extendLock: cliff more than 10 years");
        require(newVestingDuration <= 25*365, "Vault::extendLock: vesting duration more than 25 years");
        require(newVestingDuration >= newCliffDuration, "Vault::extendLock: duration < cliff");
        lock.vestingDurationInDays = newVestingDuration;
        emit LockExtended(lockId, oldVestingDuration, newVestingDuration, oldCliffDuration, newCliffDuration, lock.startTime);
    }

    /**
     * @notice Internal implementation of lockTokens
     * @param locker The account that is locking tokens
     * @param receiver The account that will be able to retrieve unlocked tokens
     * @param startTime The unix timestamp when the lock period will start
     * @param amount The amount of tokens being locked
     * @param vestingDurationInDays The vesting period in days
     * @param cliffDurationInDays The cliff duration in days
     * @param grantVotingPower if true, give user voting power from tokens
     */
    function _lockTokens(
        address token,
        address locker,
        address receiver,
        uint48 startTime,
        uint256 amount,
        uint16 vestingDurationInDays,
        uint16 cliffDurationInDays,
        bool grantVotingPower
    ) internal {

        // Transfer the tokens under the control of the vault contract
        IERC20Permit(token).safeTransferFrom(locker, address(this), amount);

        uint48 lockStartTime = startTime == 0 ? uint48(block.timestamp) : startTime;
        uint256 votingPowerGranted;
        
        // Grant voting power, if specified
        if(grantVotingPower) {
            votingPowerGranted = lockManager.grantVotingPower(receiver, token, amount);
        }

        // Create lock
        Lock memory lock = Lock({
            token: token,
            receiver: receiver,
            startTime: lockStartTime,
            vestingDurationInDays: vestingDurationInDays,
            cliffDurationInDays: cliffDurationInDays,
            amount: amount,
            amountClaimed: 0,
            votingPower: votingPowerGranted
        });

        tokenLocks[numLocks] = lock;
        lockIds[receiver].push(numLocks);
        emit LockCreated(token, locker, receiver, numLocks, amount, lockStartTime, vestingDurationInDays, cliffDurationInDays, votingPowerGranted);
        
        // Increment lock id
        numLocks++;
    }

    /**
     * @notice Internal implementation of token claims
     * @param lockId The lock id for claim
     * @param claimAmount The amount to claim
     */
    function _claimTokens(uint256 lockId, uint256 claimAmount) internal {
        Lock storage lock = tokenLocks[lockId];
        uint256 votingPowerRemoved;

        // Remove voting power, if exists
        if (lock.votingPower > 0) {
            votingPowerRemoved = lockManager.removeVotingPower(lock.receiver, lock.token, claimAmount);
            lock.votingPower = lock.votingPower - votingPowerRemoved;
        }

        // Update claimed amount
        lock.amountClaimed = lock.amountClaimed + claimAmount;

        // Release tokens
        IERC20Permit(lock.token).safeTransfer(lock.receiver, claimAmount);
        emit UnlockedTokensClaimed(lock.receiver, lock.token, lockId, claimAmount, votingPowerRemoved);
    }

    /**
     * @notice Adds uint16 to uint16 safely
     * @param a First number
     * @param b Second number
     * @param errorMessage Error message to use if numbers cannot be added
     * @return uint16 number
     */
    function _add16(uint16 a, uint16 b, string memory errorMessage) internal pure returns (uint16) {
        uint16 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }
}