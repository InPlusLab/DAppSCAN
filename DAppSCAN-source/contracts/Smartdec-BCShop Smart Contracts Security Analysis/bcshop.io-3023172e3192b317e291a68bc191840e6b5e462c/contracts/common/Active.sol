pragma solidity ^0.4.10;

import "./Owned.sol";

/**@dev Simple contract that provides active/inactive flag, its setter method 
 and modifer for certain method to be called only in active/inactive state  */
contract Active is Owned {
    
    bool public activeState;    
    
    function Active() public {
        activeState = true;
    }

    modifier activeOnly() {
        require(activeState);
        _;
    }

    modifier inactiveOnly() {
        require(!activeState);
        _;
    }

    function setActive(bool state) public ownerOnly {
        activeState = state;
    }    
}
