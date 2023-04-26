pragma solidity ^0.4.10;

contract ICheckList {
    function contains(address addr) public constant returns(bool) {return false;}
    function set(address addr, bool state) public;
}