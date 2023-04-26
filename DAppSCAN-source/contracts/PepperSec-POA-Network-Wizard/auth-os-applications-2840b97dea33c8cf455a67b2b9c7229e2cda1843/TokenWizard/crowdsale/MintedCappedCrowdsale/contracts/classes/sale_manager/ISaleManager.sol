pragma solidity ^0.4.23;

interface ISaleManager {
  function getAdmin() external view returns (address);
  function getCrowdsaleInfo() external view returns (uint, address, bool, bool);
  function isCrowdsaleFull() external view returns (bool, uint);
  function getCrowdsaleStartAndEndTimes() external view returns (uint, uint);
  function getCurrentTierInfo() external view returns (bytes32, uint, uint, uint, uint, uint, bool, bool);
  function getCrowdsaleTier(uint) external view returns (bytes32, uint, uint, uint, uint, bool, bool);
  function getTierWhitelist(uint) external view returns (uint, address[]);
  function getCrowdsaleMaxRaise() external view returns (uint, uint);
  function getCrowdsaleTierList() external view returns (bytes32[]);
  function getCrowdsaleUniqueBuyers() external view returns (uint);
  function getTierStartAndEndDates(uint) external view returns (uint, uint);
  function getTokensSold() external view returns (uint);
  function getWhitelistStatus(uint, address) external view returns (uint, uint);
}

interface SaleManagerIdx {
  function getAdmin(address, bytes32) external view returns (address);
  function getCrowdsaleInfo(address, bytes32) external view returns (uint, address, bool, bool);
  function isCrowdsaleFull(address, bytes32) external view returns (bool, uint);
  function getCrowdsaleStartAndEndTimes(address, bytes32) external view returns (uint, uint);
  function getCurrentTierInfo(address, bytes32) external view returns (bytes32, uint, uint, uint, uint, uint, bool, bool);
  function getCrowdsaleTier(address, bytes32, uint) external view returns (bytes32, uint, uint, uint, uint, bool, bool);
  function getTierWhitelist(address, bytes32, uint) external view returns (uint, address[]);
  function getCrowdsaleMaxRaise(address, bytes32) external view returns (uint, uint);
  function getCrowdsaleTierList(address, bytes32) external view returns (bytes32[]);
  function getCrowdsaleUniqueBuyers(address, bytes32) external view returns (uint);
  function getTierStartAndEndDates(address, bytes32, uint) external view returns (uint, uint);
  function getTokensSold(address, bytes32) external view returns (uint);
  function getWhitelistStatus(address, bytes32, uint, address) external view returns (uint, uint);
}
