pragma solidity ^0.4.0;

import './helpers/FakeTime.sol';

contract Something {
    function Something() {}
}

contract FakeTimeExample is FakeTime {

    uint256 public startTime;

    function changeStartTime(uint256 newStartTime) {
        startTime = newStartTime;
    }

    function startTimePassed() constant returns (bool) {
        return now > startTime;
    }

    function currentTime() constant returns(uint256) {
        return now;
    }

    function plusDays(uint256 daysAmount) constant returns(uint256) {
        return daysAmount * 1 days + now;
    }

}
// contract RTestDirectEtherSend1 {

//     mapping (address => uint256) public buyers;

//     function RTestDirectEtherSend1() {}

//     function() payable {
//         //simply write sender and value
//         buyers[msg.sender] = msg.value;
//     }
// }

// contract RTestDirectEtherSend2 {

//     event TestDirectEtherSend2Event(address sender, address receiver, uint256 amount);

//     function RTestDirectEtherSend2() {}

//     function () payable {
//         TestDirectEtherSend2Event(msg.sender, this, msg.value);
//     }
// }

// contract Parent {

//     event ParentEvent(address sender, address receiver, uint256 amount);

//     mapping (address => uint256) public buyers;

//     function buy() payable {
        
//         //simply write sender and value
//         buyers[msg.sender] = msg.value;

//         ParentEvent(msg.sender, this, msg.value);
//     }    
// }

// contract RTestDirectEtherSend3 {
    
//     Parent public parent;

//     function RTestDirectEtherSend3 (Parent _parent) {
//         parent = _parent;
//     }

//     function () payable {
//         parent.buy.value(msg.value)();
//     }
// }

contract RTestTime {
    uint256 public startTime;

    function RTestTime() {
        startTime = now;
    }

    function calcTime(uint256 durationHours) constant returns (uint256) {
        return  (durationHours * 1 hours) + startTime;
    }

    function changeStartTime(uint256 newTime) {
        startTime = newTime;
    }

    function getNowTime() constant returns (uint256) {
        return now;
    }
}

// pragma solidity ^0.4.0;


// contract RTestProduct {
    
//     event RTestProductEvent(address sender, uint256 value, uint256 number);

//     function () payable {
//         buy(1);
//     }

//     function buy(uint256 code) payable {
//         RTestProductEvent(msg.sender, msg.value, code);
//     }

//     function RTestProduct () {}
// }


// contract RTestVendor {

//     event RTestVendorEvent(address product);

//     RTestProduct [] public items;

//     function CreateProduct() returns (address) {
//         RTestProduct p = new RTestProduct();
//         items.push(p);

//         RTestVendorEvent(items[items.length - 1]);
//         return items[items.length - 1];
//     }
// }

// contract DontSendMeMoney {
//     function() {}

//     uint256 public SomeVar;

//     function DontSendMeMoney() {
//         SomeVar = 115;
//     }
// }

// contract WithParams {

//     uint256 public intParam;
//     string public strParam;

//     function WithParams(uint256 a, string s) {
//         intParam = a;
//         strParam = s;
//     }
// }