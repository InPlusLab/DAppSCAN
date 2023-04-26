pragma solidity ^0.4.18;

import "../common/Active.sol";

contract TestActive is Active {

    //
    // Storage data
    uint8 public data;



    //
    // Methods

    function TestActive() public {
        data = 0;
    }    

    function callWhenActive() public activeOnly {
        data = 1;
    }

    function callWhenInactive() public inactiveOnly {
        data = 2;
    }
}