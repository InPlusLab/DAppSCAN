pragma solidity ^0.5.2;

/*
    Utilities & Common Modifiers
*/
contract Utils {
    modifier validAddress(address _address) {
        require(_address != address(0), "ValidAddress: address invalid.");
        _;
    }
}
