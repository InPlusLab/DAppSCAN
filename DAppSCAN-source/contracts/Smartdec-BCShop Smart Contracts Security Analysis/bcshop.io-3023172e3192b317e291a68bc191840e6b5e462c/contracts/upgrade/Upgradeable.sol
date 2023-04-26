pragma solidity ^0.4.10;

import '../common/Owned.sol';

/* based on https://gist.github.com/Arachnid/4ca9da48d51e23e5cfe0f0e14dd6318f */

/**
 * Base contract that all upgradeable contracts should use.
 * 
 * Contracts implementing this interface are all called using delegatecall from
 * a dispatcher. As a result, the _sizes and _dest variables are shared with the
 * dispatcher contract, which allows the called contract to update these at will.
 * 
 * _sizes is a map of function signatures to return value sizes. Due to EVM
 * limitations, these need to be populated by the target contract, so the
 * dispatcher knows how many bytes of data to return from called functions.
 * Unfortunately, this makes variable-length return values impossible.
 * 
 * _dest is the address of the contract currently implementing all the
 * functionality of the composite contract. Contracts should update this by
 * calling the internal function `replace`, which updates _dest and calls
 * `initialize()` on the new contract.
 * 
 * When upgrading a contract, restrictions on permissible changes to the set of
 * storage variables must be observed. New variables may be added, but existing
 * ones may not be deleted or replaced. Changing variable names is acceptable.
 * Structs in arrays may not be modified, but structs in maps can be, following
 * the same rules described above.
 */
contract Upgradeable {
    mapping(bytes4=>uint32) public _sizes;
    address public _dest;
    event TestEvent(bytes4 sig, uint32 len, address sender, address target);

    /**
     * This function is called using delegatecall from the dispatcher when the
     * target contract is first initialized. It should use this opportunity to
     * insert any return data sizes in _sizes, and perform any other upgrades
     * necessary to change over from the old contract implementation (if any).
     * 
     * Implementers of this function should either perform strictly harmless,
     * idempotent operations like setting return sizes, or use some form of
     * access control, to prevent outside callers.
     */
    function initialize();
    
    /**
     * Performs a handover to a new implementing contract.
     */
    function replace(address target) internal {
        _dest = target;
        target.delegatecall(bytes4(sha3("initialize()")));
    }    
}

/**
 * The dispatcher is a minimal 'shim' that dispatches calls to a targeted
 * contract. Calls are made using 'delegatecall', meaning all storage and value
 * is kept on the dispatcher. As a result, when the target is updated, the new
 * contract inherits all the stored data and value from the old contract.
 */
contract Dispatcher is Upgradeable { 
    event TestEvent(bytes4 sig, uint32 len, address sender, address target);
    function Dispatcher(address target) {
        replace(target);
    }
    
    function initialize() {
        // Should only be called by on target contracts, not on the dispatcher
       require(false);
    }

    function changeTarget(address target) {
        replace(target);
    }

    function() {
        bytes4 sig;
        assembly { sig := calldataload(0) }        

        uint32 len = _sizes[sig];
        address target = _dest;
        bool callResult;
        //TestEvent(sig, len, msg.sender, target);
        assembly {
            // return _dest.delegatecall(msg.data)
            calldatacopy(0x0, 0x0, calldatasize)
            callResult := delegatecall(sub(gas, 10000), target, 0x0, calldatasize, 0, len)            
        }
        require (callResult);
        
        assembly {
            return(0, len)
        }
    }
}
