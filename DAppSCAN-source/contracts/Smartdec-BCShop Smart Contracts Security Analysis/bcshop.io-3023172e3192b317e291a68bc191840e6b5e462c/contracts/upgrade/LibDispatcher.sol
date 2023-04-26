pragma solidity ^0.4.10;

import "../common/Owned.sol";

/*
Based on https://blog.zeppelin.solutions/proxy-libraries-in-solidity-79fbe4b970fd

LibDispatcher is used to switch contract's that uses library to new library version

Contract should link it instead of any other library it plans upgrade

LibDispatcherStorage stores metadata for dispatching - current library version and return 
value sizes for every function that returns some result. Its address is hardcoded in LibDispatcher
 s it doesn't allowed to have its own storage in order to be able to 'delgatecall' libraries.

During deploy phase you should replace '1111222233334444555566667777888899990000' in binary data 
of LibDispatcher with address of actual LibDispatcherStorage instance omitting '0x' prefix.
*/

contract LibDispatcherStorage is Owned {
    address public lib;
    mapping(bytes4 => uint32) public sizes;
    event FunctionChanged(string name, bytes4 sig, uint32 size);

    function LibDispatcherStorage(address newLib) public {
        replace(newLib);
    }

    function replace(address newLib) public ownerOnly {
        lib = newLib;
    }

    /**@dev Adds information about function return value suze.
    IMPORTANT! 'func' parameter should contain no spaces after commas in parameters list, also no parameter names.
    
    Valid examples are:
    getVars(IExampleLib.Data storage,uint256)
    getVars(uint256)
    getVars()

    Invalid examples are
    getVars(IExampleLib.Data storage, uint256) - space after comma
    getVars(uint256 a) - parameter name
     */
    function addFunction(string func, uint32 size) public ownerOnly {
        bytes4 sig = bytes4(sha3(func));
        sizes[sig] = size;
        FunctionChanged(func, sig, size);
    }
}

contract LibDispatcher {
    //event FunctionCalled(bytes4 sig, uint32 size, address dest);

    function LibDispatcher() public {}

    function() public payable {
        LibDispatcherStorage dispatcherStorage = LibDispatcherStorage(0x1111222233334444555566667777888899990000);

        uint32 len = dispatcherStorage.sizes(msg.sig);
        address target = dispatcherStorage.lib();

        //FunctionCalled(msg.sig, len, target);
        bool callResult = false;
        assembly {
            calldatacopy(0x0, 0x0, calldatasize)
            callResult := delegatecall(sub(gas, 10000), target, 0x0, calldatasize, 0, len)
        }

        require (callResult);
        
        assembly {
            return(0, len)
        }
    }
}