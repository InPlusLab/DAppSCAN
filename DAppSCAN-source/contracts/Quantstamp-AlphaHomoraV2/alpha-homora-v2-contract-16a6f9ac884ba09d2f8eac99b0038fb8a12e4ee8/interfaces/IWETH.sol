pragma solidity 0.6.12;

interface IWETH {
  function balanceOf(address user) external returns (uint);

  function approve(address to, uint value) external returns (bool);

  function transfer(address to, uint value) external returns (bool);

  function deposit() external payable;

  function withdraw(uint) external;
}
