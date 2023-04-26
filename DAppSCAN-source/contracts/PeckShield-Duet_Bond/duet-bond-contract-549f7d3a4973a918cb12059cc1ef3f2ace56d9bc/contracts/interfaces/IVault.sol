pragma solidity >=0.8.0;

interface IVault {
  function underlying() external view  returns (address);
  function deposits(address user) external view returns (uint256);
}