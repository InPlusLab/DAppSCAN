pragma solidity >=0.4.24;


import "./Ownable.sol";


/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism. Identical to OpenZeppelin version
 * except that it uses local Ownable contract
 */
contract Pausable is Ownable {
    event Pause();
    event Unpause();

    /**
    * @dev Modifier to make a function callable only when the contract is not paused.
    */
    modifier whenNotPaused() {
        require(!isPaused(), "Contract is paused");
        _;
    }

    /**
    * @dev Modifier to make a function callable only when the contract is paused.
    */
    modifier whenPaused() {
        require(isPaused(), "Contract is not paused");
        _;
    }

    /**
    * @dev called by the owner to pause, triggers stopped state
    */
    function pause() public onlyOwner  whenNotPaused  {
        setPause(true);
        emit Pause();
    }

    /**
    * @dev called by the owner to unpause, returns to normal state
    */
    function unpause() public onlyOwner  whenPaused {
        setPause(false);
        emit Unpause();
    }

    function setPause(bool value) internal {
        bytes32 slot = keccak256(abi.encode("Pausable", "pause"));
        uint256 v = value ? 1 : 0;
        assembly {
            sstore(slot, v)
        }
    }

    function isPaused() public view returns (bool) {
        bytes32 slot = keccak256(abi.encode("Pausable", "pause"));
        uint256 v;
        assembly {
            v := sload(slot)
        }
        return v != 0;
    }
}
