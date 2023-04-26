pragma solidity ^0.4.23;

interface IAdmin {
  function getAdmin() external view returns (address);
  function getCrowdsaleInfo() external view returns (uint, address, uint, bool, bool, bool);
  function isCrowdsaleFull() external view returns (bool, uint);
  function getCrowdsaleStartAndEndTimes() external view returns (uint, uint);
  function getCrowdsaleStatus() external view returns (uint, uint, uint, uint, uint, uint, bool);
  function getTokensSold() external view returns (uint);
  function getCrowdsaleWhitelist() external view returns (uint, address[]);
  function getWhitelistStatus(address) external view returns (uint, uint);
  function getCrowdsaleUniqueBuyers() external view returns (uint);
}

interface AdminIdx {
  function getAdmin(address, bytes32) external view returns (address);
  function getCrowdsaleInfo(address, bytes32) external view returns (uint, address, uint, bool, bool, bool);
  function isCrowdsaleFull(address, bytes32) external view returns (bool, uint);
  function getCrowdsaleStartAndEndTimes(address, bytes32) external view returns (uint, uint);
  function getCrowdsaleStatus(address, bytes32) external view returns (uint, uint, uint, uint, uint, uint, bool);
  function getTokensSold(address, bytes32) external view returns (uint);
  function getCrowdsaleWhitelist(address, bytes32) external view returns (uint, address[]);
  function getWhitelistStatus(address, bytes32, address) external view returns (uint, uint);
  function getCrowdsaleUniqueBuyers(address, bytes32) external view returns (uint);
}
