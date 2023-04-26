pragma solidity ^0.4.10;

import '../common/SafeMathLib.sol';

library IExampleLib {
    struct Data {
        uint256 var1;
        uint256 var2;        
        bool var3;   
        bytes32 var4;
    }

    function getVar1(IExampleLib.Data storage self) constant returns (uint256);
    function getVars(IExampleLib.Data storage self, uint256 useless, bool useless2)  returns (uint256, uint256);
    function getAllVars(IExampleLib.Data storage self) constant returns (uint256, bool, uint256, bytes32);
    function getBool(IExampleLib.Data storage self)  returns (bool);
    function getBoolAsInt(IExampleLib.Data storage self)  returns (uint256);
    function getBytes(IExampleLib.Data storage self) returns (bytes32);

    function setVars(IExampleLib.Data storage self, uint256 new1, uint256 new2) returns (bool);
    function setVar3(IExampleLib.Data storage self, bool state);
    function setVar4(IExampleLib.Data storage self, bytes32 new4);
    function pay(IExampleLib.Data storage self);
}

library ExampleLib {
    function getVar1(IExampleLib.Data storage self) constant returns (uint256) {
        return self.var1;
    }

    function getVars(IExampleLib.Data storage self, uint256 useless, bool useless2)  returns (uint256, uint256) {
        return (self.var1, self.var2);
    }

    function getAllVars(IExampleLib.Data storage self) constant returns (uint256, bool, uint256, bytes32) {
        return (self.var1, self.var3, self.var2, self.var4);
    }

    function getBool(IExampleLib.Data storage self)  returns (bool) {
        return self.var3;
    }
    
    function getBoolAsInt(IExampleLib.Data storage self)  returns (uint256) {
        if (self.var3) {
            return 1;
        } else {
            return 0;
        }
    }
    
    function getBytes(IExampleLib.Data storage self) returns (bytes32) {
        return self.var4;
    }

    function setVars(IExampleLib.Data storage self, uint256 new1, uint256 new2)returns (bool) {        
        self.var1 = new1;
        self.var2 = new2;
        return true;
    }

    function setVar3(IExampleLib.Data storage self, bool state) {
        self.var3 = state;
    }

    function setVar4(IExampleLib.Data storage self, bytes32 new4) {
        self.var4 = new4;
    }

    function pay(IExampleLib.Data storage self) {
        require(msg.value > 10);
        self.var1 = msg.value;
    }
}

library ExampleLib2 {
    function getVar1(IExampleLib.Data storage self) constant returns (uint256) {
        return self.var1 * 2;
    }

    function getVars(IExampleLib.Data storage self, uint256 useless, bool useless2)  returns (uint256, uint256) {
        return (self.var1 * 2, self.var2 * 2);
    }

    function getAllVars(IExampleLib.Data storage self) constant returns (uint256, bool, uint256, bytes32) {
        return (self.var1, self.var3, self.var2, self.var4);
    }

    function getBool(IExampleLib.Data storage self)  returns (bool) {
        return self.var3;
    }

    function getBoolAsInt(IExampleLib.Data storage self)  returns (uint256) {
         if (self.var3) {
            return 1;
        } else {
            return 0;
        }
    }

    function getBytes(IExampleLib.Data storage self) returns (bytes32) {
        return self.var4;
    }

    function setVars(IExampleLib.Data storage self, uint256 new1, uint256 new2) returns (bool) {
        self.var1 = new1 + 1;
        self.var2 = new2 + 1;
        return true;
    }
    

    function setVar3(IExampleLib.Data storage self, bool state) {
        self.var3 = state;
    }

    function setVar4(IExampleLib.Data storage self, bytes32 new4) {
        self.var4 = new4;
    }

    function pay(IExampleLib.Data storage self) {
        self.var1 = msg.value * 2;
    }
}

//doesn't work due to incompatible struct
library ExampleLibEx {
    struct Data {
        uint256 var1;
        uint256 var2;        
        bool var3;   
        bytes32 var4;
        uint256 newVar1;
        bool newVar2;
    }

    function getVar1(ExampleLibEx.Data storage self) constant returns (uint256) {
        return self.var1;
    }
    function getVars(ExampleLibEx.Data storage self, uint256 useless, bool useless2)  returns (uint256, uint256) {
        return (self.var1, self.var2);
    }
    function getAllVars(ExampleLibEx.Data storage self) constant returns (uint256, bool, uint256, bytes32) {
        return (self.var1, self.var3, self.var2, self.var4);
    }
    function getBool(ExampleLibEx.Data storage self)  returns (bool) {
        return self.var3;
    }
    function getBoolAsInt(ExampleLibEx.Data storage self)  returns (uint256) {
        return self.var3 ? 10 : 0;
    }
    function getBytes(ExampleLibEx.Data storage self) returns (bytes32) {
        return self.var4;
    }

    function setVars(ExampleLibEx.Data storage self, uint256 new1, uint256 new2) returns (bool) {
        self.var1 = new1;
        self.var2 = new2;
        // self.newVar1 = new1 + new2;
        // self.newVar2 = true;
        return true;
    }
    function setVar3(ExampleLibEx.Data storage self, bool state) {
        self.var3 = state;
        self.newVar2 = !state;
    }
    function setVar4(ExampleLibEx.Data storage self, bytes32 new4) {
        self.var4 = new4;
    }
    function pay(ExampleLibEx.Data storage self) {}
}

contract ExampleLibDispatcherStorage {
    address public lib;
    mapping(bytes4 => uint32) public sizes;
    event FunctionChanged(string name, bytes4 sig, uint32 size);

    function ExampleLibDispatcherStorage(address newLib) {
        // addFunction("getVar1(IExampleLib.Data storage)", 32);
        // addFunction("getVars(IExampleLib.Data storage)", 32 + 32);
        replace(newLib);
    }

    function replace(address newLib) /* ownerOnly */ {
        lib = newLib;
    }

    function addFunction(string func, uint32 size) /*ownerOnly*/{
        bytes4 sig = bytes4(sha3(func));
        sizes[sig] = size;
        FunctionChanged(func, sig, size);
    }
}

contract ExampleLibDispatcher {
    event FunctionCalled(bytes4 sig, uint32 size, address dest);

    function() payable {
        ExampleLibDispatcherStorage dispatcherStorage = ExampleLibDispatcherStorage(0x1111222233334444555566667777888899990000);
        uint32 len = dispatcherStorage.sizes(msg.sig);
        address target = dispatcherStorage.lib();
        FunctionCalled(msg.sig, len, target);

        bool a = false;
        assembly {
            calldatacopy(0x0, 0x0, calldatasize)
            a := delegatecall(sub(gas, 10000), target, 0x0, calldatasize, 0, len)
        }

        require (a);
        
        assembly {
            return(0, len)
        }
    }
}

contract ExampleLibraryUser {
    using IExampleLib for IExampleLib.Data;

    event FunctionCalled(bytes4 sig, uint32 size, address dest);    
    
    IExampleLib.Data public data;    

    function ExampleLibraryUser() {

    }

    function getVar1() constant returns(uint256) {
        return data.getVar1();
    }
    
    function getVars(uint256 useless, bool useless2) returns (uint256, uint256) {
        return data.getVars(useless, useless2);
    }

    function getAllVars() constant returns (uint256, bool, uint256, bytes32) {
        return data.getAllVars();
    }

    function getBool() returns (bool) {
        return data.getBool();
    }

    function getBoolAsInt()  returns (uint256) {
        return data.getBoolAsInt();
    }

    function getBytes() returns (bytes32) {
        return data.getBytes();
    }

    function setVars(uint256 new1, uint256 new2) {
        require(data.setVars(new1, new2));
    }

    function setVar3(bool state) {
        data.setVar3(state);
    }

    function setVar4(bytes32 new4) {
        data.setVar4(new4);
    }

    function() payable {        
        data.pay();
    }
}

contract ExampleUserFactory {
    event NewExampleUser(address newUser);
    ExampleLibraryUser[] public users;

    function createNewUser() {
        ExampleLibraryUser user = new ExampleLibraryUser();
        users.push(user);
        NewExampleUser(user);
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

library SafeMathUserLib {
    struct Data {
        uint256 v1;
        uint256 v2;
    }

    using SafeMathLib for uint256;

    function getSum(SafeMathUserLib.Data storage self) returns(uint256) {
        return self.v1.safeAdd(self.v2);
        //return self.v1 + self.v2;
    }
}

contract ExampleSafeMathUser {
    using SafeMathUserLib for SafeMathUserLib.Data;
    SafeMathUserLib.Data public data;

    function setValues(uint256 a1, uint256 a2) {
        data.v1 = a1;
        data.v2 = a2;
    }
    
    function getSum() returns (uint256) {
        return data.getSum();
    }
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

