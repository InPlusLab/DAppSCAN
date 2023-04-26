pragma solidity 0.5.12;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an owner that can be granted exclusive access to
 * specific functions.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner, and the modifier `onlyManager`, which can be applied to your
 * functions to restrict their use to the manager.
 */
contract Ownable {
    address public owner;
    address public pendingOwner;
    mapping(address => bool) public managers;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SetManager(address indexed owner, address indexed newManager);
    event RemoveManager(address indexed owner, address indexed previousManager);

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "onlyOwner: non-owner");
        _;
    }

    /**
     * @dev Throws if called by any account other than a manager.
     */
    modifier onlyManager() {
        require(managers[msg.sender], "onlyOwner: non-manager");
        _;
    }

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () public {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @dev Returns true if the user(`account`) is the a manager.
     */
    function isManager(address _account) public view returns (bool) {
        return managers[_account];
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner_`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != owner, "transferOwnership: the same owner.");
        pendingOwner = _newOwner;
    }

    /**
     * @dev Accepts ownership of the contract.
     * Can only be called by the settting new owner(`pendingOwner`).
     */
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "acceptOwnership: only new owner do this.");
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    /**
     * @dev Set a new user(`account`) as a manager.
     * Can only be called by the current owner.
     */
    function setManager(address _account) external onlyOwner {
        require(_account != address(0), "setManager: account cannot be a zero address.");
        require(!isManager(_account), "setManager: Already a manager address.");
        managers[_account] = true;
        emit SetManager(owner, _account);
    }

    /**
     * @dev Remove a previous manager account.
     * Can only be called by the current owner.
     */
    function removeManager(address _account) external onlyOwner {
        require(_account != address(0), "removeManager: _account cannot be a zero address.");
        require(isManager(_account), "removeManager: Not an admin address.");
        managers[_account] = false;
        emit RemoveManager(owner, _account);
    }
}
