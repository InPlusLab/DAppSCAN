pragma solidity >=0.4.24;

import './Ownable.sol';

/**
* @title Lockable
* @dev Base contract which allows children to lock certain methods from being called by clients.
* Locked methods are deemed unsafe by default, but must be implemented in children functionality to adhere by
* some inherited standard, for example. 
*/

contract Lockable is Ownable {
	// Events
	event Unlocked();
	event Locked();

	// Modifiers
	/**
	* @dev Modifier that disables functions by default unless they are explicitly enabled
	*/
	modifier whenUnlocked() {
		require(!isLocked(), "Contact is locked");
		_;
	}

	// Methods
	/**
	* @dev called by the owner to enable method
	*/
	function unlock() public onlyOwner  {
		setLock(false);
		emit Unlocked();
	}

	/**
	* @dev called by the owner to disable method, back to normal state
	*/
	function lock() public  onlyOwner {
		setLock(true);
		emit Locked();
	}

	function setLock(bool value) internal {
        bytes32 slot = keccak256(abi.encode("Lockable", "lock"));
        uint256 v = value ? 1 : 0;
        assembly {
            sstore(slot, v)
        }
    }

    function isLocked() public view returns (bool) {
        bytes32 slot = keccak256(abi.encode("Lockable", "lock"));
        uint256 v;
        assembly {
            v := sload(slot)
        }
        return v != 0;
    }

}