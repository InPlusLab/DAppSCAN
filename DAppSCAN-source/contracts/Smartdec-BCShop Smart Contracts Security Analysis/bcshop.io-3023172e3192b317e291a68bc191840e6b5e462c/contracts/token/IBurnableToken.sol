pragma solidity ^0.4.10;

/**@dev A token that can be burnt */
contract IBurnableToken {
    function burn(uint256 _value) public;
}