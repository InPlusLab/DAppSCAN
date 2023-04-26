pragma solidity >=0.4.24;


/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions". This adds two-phase
 * ownership control to OpenZeppelin's Ownable class. In this model, the original owner 
 * designates a new owner but does not actually transfer ownership. The new owner then accepts 
 * ownership and completes the transfer.
 */
contract Ownable {
    address public owner;
    address public pendingOwner;


    event OwnershipTransferred(
      address indexed previousOwner,
      address indexed newOwner
    );


    /**
    * @dev The Ownable constructor sets the original `owner` of the contract to the sender
    * account.
    */
    constructor() public {
        owner = msg.sender;
        pendingOwner = address(0);
    }

    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier onlyOwner() {
        require(msg.sender == owner, "Account is not owner");
        _;
    }

    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner, "Account is not pending owner");
        _;
    }

    /**
    * @dev Allows the current owner to transfer control of the contract to a newOwner.
    * @param _newOwner The address to transfer ownership to.
    */
    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Empty address");
        pendingOwner = _newOwner;
    }

    /**
    * @dev Allows the pendingOwner address to finalize the transfer.
    */
    function claimOwnership() onlyPendingOwner public {
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }
}
