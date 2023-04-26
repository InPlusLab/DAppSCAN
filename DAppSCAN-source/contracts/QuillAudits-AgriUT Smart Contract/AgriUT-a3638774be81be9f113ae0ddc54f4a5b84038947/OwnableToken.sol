// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

abstract contract OwnableToken {
    address private _owner;

     event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    constructor() 
    {
        _owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == _owner);
        _;
    }

    function transferOwnership(address newOwner) onlyOwner public {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}