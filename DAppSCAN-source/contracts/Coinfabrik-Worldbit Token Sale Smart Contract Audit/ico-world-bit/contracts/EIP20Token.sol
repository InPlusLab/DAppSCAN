pragma solidity ^0.4.15;

/**
 * Interface for the standard token.
 * Based on https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
 */
contract EIP20Token {

  function totalSupply() public constant returns (uint256);
  function balanceOf(address who) public constant returns (uint256);
  function transfer(address to, uint256 value) public returns (bool success);
  function transferFrom(address from, address to, uint256 value) public returns (bool success);
  function approve(address spender, uint256 value) public returns (bool success);
  function allowance(address owner, address spender) public constant returns (uint256 remaining);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  /**
  ** Optional functions
  *
  function name() public constant returns (string name);
  function symbol() public constant returns (string symbol);
  function decimals() public constant returns (uint8 decimals);
  *
  **/

}