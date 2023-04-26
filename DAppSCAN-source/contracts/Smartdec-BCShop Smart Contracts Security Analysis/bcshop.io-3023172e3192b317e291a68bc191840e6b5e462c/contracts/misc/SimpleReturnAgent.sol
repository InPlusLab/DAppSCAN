pragma solidity ^0.4.10;

import '../token/ReturnTokenAgent.sol';

contract SimpleReturnAgent is ReturnTokenAgent {
    function SimpleReturnAgent() {}

    event ReturnEvent(address from, uint256 amountReturned);

    function() payable {}

    function returnToken(address from, uint256 amountReturned) returnableTokenOnly {
        from.transfer(1 ether);
        
        ReturnEvent(from, amountReturned);
    }
}