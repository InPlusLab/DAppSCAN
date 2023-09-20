pragma solidity ^0.5.16;

 // Taking ideas from Open Zeppelin's Pausable contract
contract Ownable {
    address public owner;
    address public ownerChanger;
    address public pendingOwner;

    event OwnershipTransferRequested(address newPendingOwner);

    event OwnershipTransferred(address oldOwner, address newOwner);

    // The Ownable constructor sets the `ownerChanger` and the original `owner` of the contract.
    constructor (address newOwnerChanger) public {
        owner = msg.sender;
        ownerChanger = newOwnerChanger;
    }

    // Modifier to make a function callable only by owner
    modifier onlyOwner() {
        require(msg.sender == owner, 'Sender should be Owner');
        _;
    }

    // Allows the current owner to transfer control of the contract to a newOwner. (It should be accepted by OwnerChanger)
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0),'New owner can not be zero address');
        pendingOwner = newOwner;

        emit OwnershipTransferRequested(newOwner);
    }
//SWC-114-Transaction Order Dependence:L26-31,34-42
    // Owner changer can accept if owner call transferOwnership function
    function acceptTransferOwnership () external {
        require (msg.sender == ownerChanger, 'Sender should be ownerChanger');
        require (pendingOwner != address(0), 'Pending Owner is empty');
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);

        emit OwnershipTransferred(oldOwner, pendingOwner);
    }
}