pragma solidity ^0.4.0;

contract Exception {
    function() payable {
        if(true) throw;
    }
}
