import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';

pragma solidity ^0.5.10;

contract Medianizer {
    function peek() public view returns (bytes32, bool);
    function read() public returns (bytes32);
    function poke() public;
    function poke(bytes32) public;
    function fund (uint256 amount, ERC20 token) public;
}
