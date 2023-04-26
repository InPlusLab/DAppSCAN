pragma solidity ^0.4.10;

import '../upgrade/Upgradeable.sol';


/* Example contracts storage scheme */
contract ExampleStorage {
    uint public _value;
    uint public _value2;
}

/* Dispatcher for Example contracts */
contract ExampleDispatcher is ExampleStorage, Dispatcher {    

    function ExampleDispatcher(address target) 
        Dispatcher(target) {
    }
    
    function initialize() {
        _sizes[bytes4(sha3("getUint()"))] = 32;
        _sizes[bytes4(sha3("getValues()"))] = 32 + 32;
    }
}

/* Example contracts interface */
contract IExample {
    function getUint() returns (uint);
    function getValues() returns (uint256 v1, uint256 v2);
    function setUint(uint value);
    event TestEvent(bytes4 sig, uint32 len, address sender, address target);
}

/* Base version of Example class */
contract ExampleV1 is ExampleStorage, IExample, Upgradeable {

    function ExampleV1() {}
    
    function initialize() {
        _sizes[bytes4(sha3("getUint()"))] = 32;
        _sizes[bytes4(sha3("getValues()"))] = 32 + 32;
    }
    
    function getUint() returns (uint) {
        return _value;
    }

    function getValues() returns (uint256 v1, uint256 v2) {
        v1 = _value;
        v2 = 2;
    }
    
    function setUint(uint value) {
        _value = value;
    }
}

/* The 'upgraded' version of ExampleV1 which modifies getUint to return _value+10  */
contract ExampleV2 is ExampleStorage, IExample, Upgradeable {    
    
    function ExampleV2() {}

    function initialize() {
        _sizes[bytes4(sha3("getUint()"))] = 32;
        _sizes[bytes4(sha3("getValues()"))] = 32 + 32;
    }
    
    function getUint() returns (uint) {
        return _value + 10;
    }

    function getValues() returns (uint256 v1, uint256 v2) {
        v1 = 100;
        v2 = _value;
    }
    
    function setUint(uint value) {
        _value = value;
    }
}

// contract DispatcherUser is ExampleStorage, IExample, Upgradeable {
    
//     function DispatcherUser(address target) {
//         _dest = target;
//     }

//     function getUint() returns (uint) {
//         return _dest.delegatecall(bytes4(sha3("getUint()")));
//     }

//     function getValues() returns (uint256 v1, uint256 v2) {
//         v1 = 100;
//         v2 = _value;
//     }
    
//     function setUint(uint value) {
//         _value = value;
//     }
// }