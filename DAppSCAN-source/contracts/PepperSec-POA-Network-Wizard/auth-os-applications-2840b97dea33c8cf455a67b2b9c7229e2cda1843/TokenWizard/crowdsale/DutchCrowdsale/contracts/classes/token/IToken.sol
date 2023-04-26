pragma solidity ^0.4.23;

interface IToken {
  function name() external view returns (string);
  function symbol() external view returns (string);
  function decimals() external view returns (uint8);
  function totalSupply() external view returns (uint);
  function balanceOf(address) external view returns (uint);
  function allowance(address, address) external view returns (uint);
  function transfer(address, uint) external returns (bool);
  function transferFrom(address, address, uint) external returns (bool);
  function approve(address, uint) external returns (bool);
  function increaseApproval(address, uint) external returns (bool);
  function decreaseApproval(address, uint) external returns (bool);
  event Transfer(address indexed from, address indexed to, uint amt);
  event Approval(address indexed owner, address indexed spender, uint amt);
}

interface TokenIdx {
  function name(address, bytes32) external view returns (bytes32);
  function symbol(address, bytes32) external view returns (bytes32);
  function decimals(address, bytes32) external view returns (uint8);
  function totalSupply(address, bytes32) external view returns (uint);
  function balanceOf(address, bytes32, address) external view returns (uint);
  function allowance(address, bytes32, address, address) external view returns (uint);
}
