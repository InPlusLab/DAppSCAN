pragma solidity ^0.4.24;


/**
 * @title ERC223 Receiver Interface 
 */
contract IERC223Receiver {
    function tokenFallback(address from, uint value, bytes data) public;
}