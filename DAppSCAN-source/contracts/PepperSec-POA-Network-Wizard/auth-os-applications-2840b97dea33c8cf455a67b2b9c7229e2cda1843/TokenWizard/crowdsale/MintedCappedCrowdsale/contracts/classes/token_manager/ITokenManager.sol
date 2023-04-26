pragma solidity ^0.4.23;

interface ITokenManager {
  function getReservedTokenDestinationList() external view returns (uint, address[]);
  function getReservedDestinationInfo(address) external view returns (uint, uint, uint, uint);
}

interface TokenManagerIdx {
  function getReservedTokenDestinationList(address, bytes32) external view returns (uint, address[]);
  function getReservedDestinationInfo(address, bytes32, address) external view returns (uint, uint, uint, uint);
}
