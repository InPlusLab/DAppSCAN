// contracts/LockletTokenVault.sol
// SPDX-License-Identifier: No License
// SWC-103-Floating Pragma: L4
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./LockletToken.sol";

contract LockletTokenVault is AccessControl, Pausable {
    using SafeMath for uint256;
    using SafeMath for uint16;

    using SignedSafeMath for int256;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    address public lockletTokenAddress;

    struct RecipientCallData {
        address recipientAddress;
        uint256 amount;
    }

    struct Recipient {
        address recipientAddress;
        uint256 amount;
        uint16 daysClaimed;
        uint256 amountClaimed;
        bool isActive;
    }

    struct Lock {
        uint256 creationTime;
        address tokenAddress;
        uint256 startTime;
        uint16 durationInDays;
        address initiatorAddress;
        bool isRevocable;
        bool isRevoked;
        bool isActive;
    }

    struct LockWithRecipients {
        uint256 index;
        Lock lock;
        Recipient[] recipients;
    }

    uint256 private _nextLockIndex;
    Lock[] private _locks;
    mapping(uint256 => Recipient[]) private _locksRecipients;

    mapping(address => uint256[]) private _initiatorsLocksIndexes;
    mapping(address => uint256[]) private _recipientsLocksIndexes;

    mapping(address => mapping(address => uint256)) private _refunds;

    address private _stakersRedisAddress;
    address private _foundationRedisAddress;
    bool private _isDeprecated;

    // #region Governance Variables

    uint256 private _creationFlatFeeLktAmount;
    uint256 private _revocationFlatFeeLktAmount;

    uint256 private _creationPercentFee;

    // #endregion

    // #region Events

    event LockAdded(uint256 lockIndex);
    event LockedTokensClaimed(uint256 lockIndex, address indexed recipientAddress, uint256 claimedAmount);
    event LockRevoked(uint256 lockIndex, uint256 unlockedAmount, uint256 remainingLockedAmount);
    event LockRefundPulled(address indexed recipientAddress, address indexed tokenAddress, uint256 refundedAmount);

    // #endregion

    constructor(address lockletTokenAddr) {
        lockletTokenAddress = lockletTokenAddr;

        _nextLockIndex = 0;

        _stakersRedisAddress = address(0);
        _foundationRedisAddress = 0x25Bd291bE258E90e7A0648aC5c690555aA9e8930;
        _isDeprecated = false;

        _creationFlatFeeLktAmount = 0;
        _revocationFlatFeeLktAmount = 0;
        _creationPercentFee = 35;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GOVERNOR_ROLE, msg.sender);
    }

    function addLock(
        address tokenAddress,
        uint256 totalAmount,
        uint16 cliffInDays,
        uint16 durationInDays,
        RecipientCallData[] calldata recipientsData,
        bool isRevocable,
        bool payFeesWithLkt
    ) external whenNotPaused contractNotDeprecated {
        require(Address.isContract(tokenAddress), "LockletTokenVault: Token address is not a contract");
        ERC20 token = ERC20(tokenAddress);

        require(totalAmount > 0, "LockletTokenVault: The total amount is equal to zero");

        if (payFeesWithLkt) {
            LockletToken lktToken = lockletToken();
            require(lktToken.balanceOf(msg.sender) >= _creationFlatFeeLktAmount, "LockletTokenVault: Not enough LKT to pay fees");
            require(lktToken.transferFrom(msg.sender, address(this), _creationFlatFeeLktAmount));

            uint256 burnAmount = _creationFlatFeeLktAmount.div(100).mul(45);
            uint256 stakersRedisAmount = _creationFlatFeeLktAmount.div(100).mul(45);
            uint256 foundationRedisAmount = _creationFlatFeeLktAmount.div(100).mul(10);

            require(lktToken.burn(burnAmount));
            require(lktToken.transfer(_stakersRedisAddress, stakersRedisAmount));
            require(lktToken.transfer(_foundationRedisAddress, foundationRedisAmount));

            require(token.balanceOf(msg.sender) >= totalAmount, "LockletTokenVault: Token insufficient balance");
            require(token.transferFrom(msg.sender, address(this), totalAmount));
        } else {
            uint256 creationPercentFeeAmount = totalAmount.div(10000).mul(_creationPercentFee);
            uint256 totalAmountWithFees = totalAmount.add(creationPercentFeeAmount);

            require(token.balanceOf(msg.sender) >= totalAmountWithFees, "LockletTokenVault: Token insufficient balance");
            require(token.transferFrom(msg.sender, address(this), totalAmountWithFees));

            uint256 stakersRedisAmount = creationPercentFeeAmount.div(100).mul(90);
            uint256 foundationRedisAmount = creationPercentFeeAmount.div(100).mul(10);

            require(token.transfer(_stakersRedisAddress, stakersRedisAmount));
            require(token.transfer(_foundationRedisAddress, foundationRedisAmount));
        }

        uint256 lockIndex = _nextLockIndex;
        _nextLockIndex = _nextLockIndex.add(1);

        Lock memory lock = Lock({
            creationTime: blockTime(),
            tokenAddress: tokenAddress,
            startTime: blockTime().add(cliffInDays * 1 days),
            durationInDays: durationInDays,
            initiatorAddress: msg.sender,
            isRevocable: durationInDays > 1 ? isRevocable : false,
            isRevoked: false,
            isActive: true
        });

        _locks.push(lock);
        _initiatorsLocksIndexes[msg.sender].push(lockIndex);

        uint256 totalAmountCheck = 0;

        // SWC-128-DoS With Block Gas Limit: L166 - L184
        for (uint256 i = 0; i < recipientsData.length; i++) {
            RecipientCallData calldata recipientData = recipientsData[i];

            uint256 unlockedAmountPerDay = recipientData.amount.div(durationInDays);
            require(unlockedAmountPerDay > 0, "LockletTokenVault: The unlocked amount per day is equal to zero");

            totalAmountCheck = totalAmountCheck.add(recipientData.amount);

            Recipient memory recipient = Recipient({
                recipientAddress: recipientData.recipientAddress,
                amount: recipientData.amount,
                daysClaimed: 0,
                amountClaimed: 0,
                isActive: true
            });

            _recipientsLocksIndexes[recipientData.recipientAddress].push(lockIndex);
            _locksRecipients[lockIndex].push(recipient);
        }

        require(totalAmountCheck == totalAmount, "LockletTokenVault: The calculated total amount is not equal to the actual total amount");

        emit LockAdded(lockIndex);
    }

    function claimLockedTokens(uint256 lockIndex) external whenNotPaused {
        Lock storage lock = _locks[lockIndex];
        require(lock.isActive == true, "LockletTokenVault: Lock not existing");
        require(lock.isRevoked == false, "LockletTokenVault: This lock has been revoked");

        Recipient[] storage recipients = _locksRecipients[lockIndex];

        int256 recipientIndex = getRecipientIndexByAddress(recipients, msg.sender);
        require(recipientIndex != -1, "LockletTokenVault: Forbidden");

        Recipient storage recipient = recipients[uint256(recipientIndex)];

        uint16 daysVested;
        uint256 unlockedAmount;
        (daysVested, unlockedAmount) = calculateClaim(lock, recipient);
        require(unlockedAmount > 0, "LockletTokenVault: The amount of unlocked tokens is equal to zero");

        recipient.daysClaimed = uint16(recipient.daysClaimed.add(daysVested));
        recipient.amountClaimed = uint256(recipient.amountClaimed.add(unlockedAmount));

        ERC20 token = ERC20(lock.tokenAddress);

        require(token.transfer(recipient.recipientAddress, unlockedAmount), "LockletTokenVault: Unlocked tokens transfer failed");
        emit LockedTokensClaimed(lockIndex, recipient.recipientAddress, unlockedAmount);
    }

    function revokeLock(uint256 lockIndex) external whenNotPaused {
        Lock storage lock = _locks[lockIndex];
        require(lock.isActive == true, "LockletTokenVault: Lock not existing");
        require(lock.initiatorAddress == msg.sender, "LockletTokenVault: Forbidden");
        require(lock.isRevocable == true, "LockletTokenVault: Lock not revocable");
        require(lock.isRevoked == false, "LockletTokenVault: This lock has already been revoked");

        lock.isRevoked = true;

        LockletToken lktToken = lockletToken();
        require(lktToken.balanceOf(msg.sender) >= _revocationFlatFeeLktAmount, "LockletTokenVault: Not enough LKT to pay fees");
        require(lktToken.transferFrom(msg.sender, address(this), _revocationFlatFeeLktAmount));

        uint256 burnAmount = _creationFlatFeeLktAmount.div(100).mul(45);
        uint256 stakersRedisAmount = _creationFlatFeeLktAmount.div(100).mul(45);
        uint256 foundationRedisAmount = _creationFlatFeeLktAmount.div(100).mul(10);

        require(lktToken.burn(burnAmount));
        require(lktToken.transfer(_stakersRedisAddress, stakersRedisAmount));
        require(lktToken.transfer(_foundationRedisAddress, foundationRedisAmount));

        Recipient[] storage recipients = _locksRecipients[lockIndex];

        address tokenAddr = lock.tokenAddress;
        address initiatorAddr = lock.initiatorAddress;

        uint256 totalAmount = 0;
        uint256 totalUnlockedAmount = 0;

        // SWC-128-DoS With Block Gas Limit: L247 - L262
        for (uint256 i = 0; i < recipients.length; i++) {
            Recipient storage recipient = recipients[i];

            totalAmount = totalAmount.add(recipient.amount);

            uint16 daysVested;
            uint256 unlockedAmount;
            (daysVested, unlockedAmount) = calculateClaim(lock, recipient);

            if (unlockedAmount > 0) {
                address recipientAddr = recipient.recipientAddress;
                _refunds[recipientAddr][tokenAddr] = _refunds[recipientAddr][tokenAddr].add(unlockedAmount);
            }

            totalUnlockedAmount = totalUnlockedAmount.add(recipient.amountClaimed.add(unlockedAmount));
        }

        uint256 totalLockedAmount = totalAmount.sub(totalUnlockedAmount);
        _refunds[initiatorAddr][tokenAddr] = _refunds[initiatorAddr][tokenAddr].add(totalLockedAmount);

        emit LockRevoked(lockIndex, totalUnlockedAmount, totalLockedAmount);
    }

    function pullRefund(address tokenAddress) external whenNotPaused {
        uint256 refundAmount = getRefundAmount(tokenAddress);
        require(refundAmount > 0, "LockletTokenVault: No refund found for this token");

        _refunds[msg.sender][tokenAddress] = 0;

        ERC20 token = ERC20(tokenAddress);
        require(token.transfer(msg.sender, refundAmount), "LockletTokenVault: Refund tokens transfer failed");

        emit LockRefundPulled(msg.sender, tokenAddress, refundAmount);
    }

    // #region Views

    function getLock(uint256 lockIndex) public view returns (LockWithRecipients memory) {
        Lock storage lock = _locks[lockIndex];
        require(lock.isActive == true, "LockletTokenVault: Lock not existing");

        return LockWithRecipients({index: lockIndex, lock: lock, recipients: _locksRecipients[lockIndex]});
    }

    function getLocksLength() public view returns (uint256) {
        return _locks.length;
    }

    function getLocks(int256 page, int256 pageSize) public view returns (LockWithRecipients[] memory) {
        require(getLocksLength() > 0, "LockletTokenVault: There is no lock");

        int256 queryStartLockIndex = int256(getLocksLength()).sub(pageSize.mul(page)).add(pageSize).sub(1);
        require(queryStartLockIndex >= 0, "LockletTokenVault: Out of bounds");

        int256 queryEndLockIndex = queryStartLockIndex.sub(pageSize).add(1);
        if (queryEndLockIndex < 0) {
            queryEndLockIndex = 0;
        }

        int256 currentLockIndex = queryStartLockIndex;
        require(uint256(currentLockIndex) <= getLocksLength().sub(1), "LockletTokenVault: Out of bounds");

        LockWithRecipients[] memory results = new LockWithRecipients[](uint256(pageSize));
        uint256 index = 0;
        
        // SWC-128-DoS With Block Gas Limit: L313 - L320
        for (currentLockIndex; currentLockIndex >= queryEndLockIndex; currentLockIndex--) {
            uint256 currentLockIndexAsUnsigned = uint256(currentLockIndex);
            if (currentLockIndexAsUnsigned <= getLocksLength().sub(1)) {
                results[index] = getLock(currentLockIndexAsUnsigned);
            }

            index++;
        }

        return results;
    }

    function getLocksByInitiator(address initiatorAddress) public view returns (LockWithRecipients[] memory) {
        uint256 initiatorLocksLength = _initiatorsLocksIndexes[initiatorAddress].length;
        require(initiatorLocksLength > 0, "LockletTokenVault: The initiator has no lock");

        LockWithRecipients[] memory results = new LockWithRecipients[](initiatorLocksLength);

        // SWC-128-DoS With Block Gas Limit: L332 - L335
        for (uint index = 0; index < initiatorLocksLength; index++) {
            uint256 lockIndex = _initiatorsLocksIndexes[initiatorAddress][index];
            results[index] = getLock(lockIndex);
        }

        return results;
    }

    function getLocksByRecipient(address recipientAddress) public view returns (LockWithRecipients[] memory) {        
        uint256 recipientLocksLength = _recipientsLocksIndexes[recipientAddress].length;
        require(recipientLocksLength > 0, "LockletTokenVault: The recipient has no lock");

        LockWithRecipients[] memory results = new LockWithRecipients[](recipientLocksLength);

        // SWC-128-DoS With Block Gas Limit: L347 - L350
        for (uint index = 0; index < recipientLocksLength; index++) {
            uint256 lockIndex = _recipientsLocksIndexes[recipientAddress][index];
            results[index] = getLock(lockIndex);
        }

        return results;
    }

    function getRefundAmount(address tokenAddress) public view returns (uint256) {
        return _refunds[msg.sender][tokenAddress];
    }

    function getClaimByLockAndRecipient(uint256 lockIndex, address recipientAddress) public view returns (uint16, uint256) {
        Lock storage lock = _locks[lockIndex];
        require(lock.isActive == true, "LockletTokenVault: Lock not existing");

        Recipient[] storage recipients = _locksRecipients[lockIndex];

        int256 recipientIndex = getRecipientIndexByAddress(recipients, recipientAddress);
        require(recipientIndex != -1, "LockletTokenVault: Forbidden");

        Recipient storage recipient = recipients[uint256(recipientIndex)];

        uint16 daysVested;
        uint256 unlockedAmount;
        (daysVested, unlockedAmount) = calculateClaim(lock, recipient);

        return (daysVested, unlockedAmount);
    }

    function getCreationFlatFeeLktAmount() public view returns (uint256) {
        return _creationFlatFeeLktAmount;
    }

    function getRevocationFlatFeeLktAmount() public view returns (uint256) {
        return _revocationFlatFeeLktAmount;
    }

    function getCreationPercentFee() public view returns (uint256) {
        return _creationPercentFee;
    }

    function isDeprecated() public view returns (bool) {
        return _isDeprecated;
    }

    function getRecipientIndexByAddress(Recipient[] storage recipients, address recipientAddress) private view returns (int256) {
        int256 recipientIndex = -1;
        // SWC-128-DoS With Block Gas Limit: L393 - L398
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i].recipientAddress == recipientAddress) {
                recipientIndex = int256(i);
                break;
            }
        }
        return recipientIndex;
    }

    function calculateClaim(Lock storage lock, Recipient storage recipient) private view returns (uint16, uint256) {
        require(recipient.amountClaimed < recipient.amount, "LockletTokenVault: The recipient has already claimed the maximum amount");

        // SWC-116-Block values as a proxy for time: L410
        if (block.timestamp < lock.startTime) {
            return (0, 0);
        }

        // check if cliff has reached
        uint256 elapsedDays = blockTime().sub(lock.startTime - 1 days).div(1 days);

        if (elapsedDays >= lock.durationInDays) {
            // if over duration, all tokens vested
            uint256 remainingAmount = recipient.amount.sub(recipient.amountClaimed);
            return (lock.durationInDays, remainingAmount);
        } else {
            uint16 daysVested = uint16(elapsedDays.sub(recipient.daysClaimed));
            uint256 unlockedAmountPerDay = recipient.amount.div(uint256(lock.durationInDays));
            uint256 unlockedAmount = uint256(daysVested.mul(unlockedAmountPerDay));
            return (daysVested, unlockedAmount);
        }
    }

    function blockTime() private view returns (uint256) {
        // SWC-116-Block values as a proxy for time: 430
        return block.timestamp;
    }

    function lockletToken() private view returns (LockletToken) {
        return LockletToken(lockletTokenAddress);
    }

    // #endregion

    // #region Governance

    function setCreationFlatFeeLktAmount(uint256 amount) external onlyGovernor {
        _creationFlatFeeLktAmount = amount;
    }

    function setRevocationFlatFeeLktAmount(uint256 amount) external onlyGovernor {
        _revocationFlatFeeLktAmount = amount;
    }

    function setCreationPercentFee(uint256 amount) external onlyGovernor {
        _creationPercentFee = amount;
    }

    function setStakersRedisAddress(address addr) external onlyGovernor {
        _stakersRedisAddress = addr;
    }

    function pause() external onlyGovernor {
        _pause();
    }

    function unpause() external onlyGovernor {
        _unpause();
    }

    function setDeprecated(bool deprecated) external onlyGovernor {
        _isDeprecated = deprecated;
    }

    // #endregion

    // #region Modifiers

    modifier onlyGovernor {
        require(hasRole(GOVERNOR_ROLE, msg.sender), "LockletTokenVault: Caller is not a GOVERNOR");
        _;
    }

    modifier contractNotDeprecated {
        require(!_isDeprecated, "LockletTokenVault: This version of the contract is deprecated");
        _;
    }

    // #endregion
}
