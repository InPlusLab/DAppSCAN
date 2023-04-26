// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import '@openzeppelin/contracts/math/SafeMath.sol';

/// @title Locks the registry for a minimum period of time
contract Timelock {
    using SafeMath for uint256;

    event NewAdmin(address indexed newAdmin);
    event NewPendingAdmin(address indexed newPendingAdmin);
    event NewDelay(uint256 indexed newDelay);
    event CancelTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );
    event ExecuteTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );
    event QueueTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );

    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MINIMUM_DELAY = 6 hours;
    uint256 public constant MAXIMUM_DELAY = 30 days;

    uint256 public delay;
    address public admin;
    address public pendingAdmin;
    mapping(address => bool) public pendingAdminAccepted;
    mapping(bytes32 => bool) public queuedTransactions;

    constructor(address _admin, uint256 _delay) {
        require(_delay >= MINIMUM_DELAY, 'Timelock::constructor: Delay must exceed minimum delay.');
        require(_delay <= MAXIMUM_DELAY, 'Timelock::constructor: Delay must not exceed maximum delay.');

        admin = _admin;
        delay = _delay;
    }

    /// @notice Sets the minimum time delay
    /// @param _delay the new delay
    function setDelay(uint256 _delay) public onlyAdmin {
        require(_delay >= MINIMUM_DELAY, 'Timelock::setDelay: Delay must exceed minimum delay.');
        require(_delay <= MAXIMUM_DELAY, 'Timelock::setDelay: Delay must not exceed maximum delay.');
        delay = _delay;

        emit NewDelay(delay);
    }

    /// @notice Sets a new address as pending admin
    /// @param _pendingAdmin the pending admin
    function setNewPendingAdmin(address _pendingAdmin) public onlyAdmin {
        pendingAdmin = _pendingAdmin;
        pendingAdminAccepted[_pendingAdmin] = false;

        emit NewPendingAdmin(pendingAdmin);
    }

    /// @notice Pending admin accepts its role of new admin
    function acceptAdminRole() public {
        require(msg.sender == pendingAdmin, 'Timelock::acceptAdminRole: Call must come from pendingAdmin.');
        pendingAdminAccepted[msg.sender] = true;
    }

    /// @notice Confirms the pending admin as new admin after he accepted the role
    function confirmNewAdmin() public onlyAdmin {
        require(
            pendingAdminAccepted[pendingAdmin],
            'Timelock::confirmNewAdmin: Pending admin must accept admin role first.'
        );
        admin = pendingAdmin;
        pendingAdmin = address(0);
        pendingAdminAccepted[pendingAdmin] = false;

        emit NewAdmin(admin);
    }

    /// @notice queues a transaction to be executed after the delay passed
    /// @param target the target contract address
    /// @param value the value to be sent
    /// @param signature the signature of the transaction to be enqueued
    /// @param data the data of the transaction to be enqueued
    /// @param eta the minimum timestamp at which the transaction can be executed
    /// @return the hash of the transaction in bytes
    function queueTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) public onlyAdmin returns (bytes32) {
        require(
            eta >= getBlockTimestamp().add(delay),
            'Timelock::queueTransaction: Estimated execution block must satisfy delay.'
        );

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
        return txHash;
    }

    /// @notice cancels a transaction that has been queued
    /// @param target the target contract address
    /// @param value the value to be sent
    /// @param signature the signature of the transaction to be enqueued
    /// @param data the data of the transaction to be enqueued
    /// @param eta the minimum timestamp at which the transaction can be executed
    function cancelTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) public onlyAdmin {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    /// @notice executes a transaction that has been queued
    /// @param target the target contract address
    /// @param value the value to be sent
    /// @param signature the signature of the transaction to be enqueued
    /// @param data the data of the transaction to be enqueued
    /// @param eta the minimum timestamp at which the transaction can be executed
    /// @return the bytes returned by the call method
    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) public payable onlyAdmin returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "Timelock::executeTransaction: Transaction hasn't been queued.");
        require(getBlockTimestamp() >= eta, "Timelock::executeTransaction: Transaction hasn't surpassed time lock.");
        require(getBlockTimestamp() <= eta.add(GRACE_PERIOD), 'Timelock::executeTransaction: Transaction is stale.');

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, 'Timelock::executeTransaction: Transaction execution reverted.');

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }

    /// @notice gets the current block timestamp
    /// @return the current block timestamp
    function getBlockTimestamp() internal view returns (uint256) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }

    /// @notice modifier to check if the sender is the admin
    modifier onlyAdmin() {
        require(msg.sender == admin, 'Timelock::onlyAdmin: Call must come from admin.');
        _;
    }
}
