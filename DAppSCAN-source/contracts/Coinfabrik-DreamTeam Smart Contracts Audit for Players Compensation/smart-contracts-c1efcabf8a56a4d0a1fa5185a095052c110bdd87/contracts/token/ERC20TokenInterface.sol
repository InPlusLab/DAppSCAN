pragma solidity ^0.4.18;

contract ERC20TokenInterface {

    function totalSupply () public constant returns (uint);
    function balanceOf (address tokenOwner) public constant returns (uint balance);
    function transfer (address to, uint tokens) public returns (bool success);
    function transferFrom (address from, address to, uint tokens) public returns (bool success);

}