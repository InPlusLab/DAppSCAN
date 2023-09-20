pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./ITimelock.sol";
import "hardhat/console.sol";

contract SafeGuard is AccessControlEnumerable {

    // Request info event
    event QueueTransactionWithDescription(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta, string description);

    bytes32 public constant SAFEGUARD_ADMIN_ROLE = keccak256("SAFEGUARD_ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELER_ROLE = keccak256("CANCELER_ROLE");
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

    ///@dev The address of the Timelock
    ITimelock public timelock;

    /**
     * @dev Initializes the contract with a given Timelock address and administrator address.
     */
    constructor (address _admin, bytes32[] memory roles, address[] memory rolesAssignees) {
        require(roles.length == rolesAssignees.length, "SafeGuard::constructor: roles assignment arity mismatch");
        // set roles administrator
        _setRoleAdmin(SAFEGUARD_ADMIN_ROLE, SAFEGUARD_ADMIN_ROLE);
        _setRoleAdmin(PROPOSER_ROLE, SAFEGUARD_ADMIN_ROLE);
        _setRoleAdmin(EXECUTOR_ROLE, SAFEGUARD_ADMIN_ROLE);
        _setRoleAdmin(CANCELER_ROLE, SAFEGUARD_ADMIN_ROLE);
        _setRoleAdmin(CREATOR_ROLE, SAFEGUARD_ADMIN_ROLE);

        // assign roles 
        for (uint i = 0; i < roles.length; i++) {
            _setupRole(roles[i], rolesAssignees[i]);
        }

        // set admin rol to an address
        _setupRole(SAFEGUARD_ADMIN_ROLE, _admin);
        _setupRole(CREATOR_ROLE, msg.sender);
    }

    /**
     * @dev Modifier to make a function callable just by a certain role.
     */
    modifier justByRole(bytes32 role) {
        require(hasRole(role, _msgSender()), "SafeGuard: sender requires permission");
        _;
    }

    /**
     * @notice Sets the timelock address this safeGuard contract is gonna use
     * @param _timelock The address of the timelock contract
     */
    function setTimelock(address _timelock) public justByRole(CREATOR_ROLE) {
        require(address(timelock) == address(0), "SafeGuard::setTimelock: Timelock address already defined");
        // set timelock address
        timelock = ITimelock(_timelock);
    }

    function queueTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta) public justByRole(PROPOSER_ROLE) {
        //SWC-135-Code With No Effects: L63-L64
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        _queueTimelockTransaction(txHash, target, value, signature, data, eta);
    }

    function queueTransactionWithDescription(address target, uint256 value, string memory signature, bytes memory data, uint256 eta, string memory description) public justByRole(PROPOSER_ROLE) {
        //SWC-135-Code With No Effects: L69-L71
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        _queueTimelockTransaction(txHash, target, value, signature, data, eta);
        emit QueueTransactionWithDescription(txHash, target, value, signature, data, eta, description);
    }

    function cancelTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public justByRole(CANCELER_ROLE) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        _cancelTimelockTransaction(txHash, target, value, signature, data, eta);
    }

    function executeTransaction(address target, uint256 _value, string memory signature, bytes memory data, uint256 eta) public payable justByRole(EXECUTOR_ROLE) {
        bytes32 txHash = keccak256(abi.encode(target, _value, signature, data, eta));
        require(timelock.queuedTransactions(txHash), "SafeGuard::executeTransaction: transaction should be queued");
        timelock.executeTransaction{value: _value, gas: gasleft()}(target, _value, signature, data, eta);
    }

    function _queueTimelockTransaction(bytes32 txHash, address target, uint256 value, string memory signature, bytes memory data, uint256 eta) private {
        require(!timelock.queuedTransactions(txHash), "SafeGuard::queueTransaction: transaction already queued at eta");
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    function _cancelTimelockTransaction(bytes32 txHash, address target, uint256 value, string memory signature, bytes memory data, uint256 eta) private {
        require(timelock.queuedTransactions(txHash), "SafeGuard::cancelTransaction: transaction should be queued");
        timelock.cancelTransaction(target, value, signature, data, eta);
    }
}