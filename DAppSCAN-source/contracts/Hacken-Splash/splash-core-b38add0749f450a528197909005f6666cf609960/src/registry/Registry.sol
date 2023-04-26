// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/access/Ownable.sol";
import "../interfaces/IRegistry.sol";

/**
  @title Registry
  @notice Registry of contract and addresses that have admin privileges
*/
contract Registry is IRegistry, Ownable {
  IRNG private _rng;
  ISP20 private _sp20;
  ISP721 private _sp721;
  ISP1155 private _sp1155;
  IStaking private _staking;
  IManagement private _management;

  mapping(address => bool) public coreAddresses;
  mapping(address => bool) public authorizedContracts;

  constructor() {
    giveCoreAccess(msg.sender);
    giveAuthorization(msg.sender);
  }

  // RNG
  function rng() external view override returns(IRNG) { return _rng; }
  function setRng(IRNG newRng) external onlyOwner { _rng = newRng; } 

  // SP20
  function sp20() external view override returns(ISP20) { return _sp20; }
  function setSp20(ISP20 newSp20) external onlyOwner { _sp20 = newSp20; }

  // SP721
  function sp721() external view override returns(ISP721) { return _sp721; }
  function setSp721(ISP721 newSp721) external onlyOwner { 
    // Deauthorize the old contract
    authorizedContracts[address(_sp721)] = false;
    
    _sp721 = newSp721;
    
    // Authorize the new contract
    authorizedContracts[address(_sp721)] = true;
  }

  // SP1155
  function sp1155() external view override returns(ISP1155) { return _sp1155; }
  function setSp1155(ISP1155 newSp1155) external onlyOwner { _sp1155 = newSp1155; }

  // Staking
  function staking() external view override returns(IStaking) { return _staking; }
  function setStaking(IStaking newStaking) external onlyOwner { _staking = newStaking; }

  // Management
  function management() external view override returns(IManagement) { return _management; }
  function setManagement(IManagement newManagement) external onlyOwner {
    // Deauthorize the old contract
    authorizedContracts[address(_management)] = false;

    _management = newManagement; 
    
    // Authorize the new contract
    authorizedContracts[address(_management)] = true;
  }

  // Core Addresses
  function core(address user) external view override returns(bool) {
    return coreAddresses[user];
  } 

  function giveCoreAccess(address user) public onlyOwner {
    require(!coreAddresses[user], "User already has access");
    coreAddresses[user] = true;
  }

  function revokeCoreAccess(address user) external onlyOwner {
    require(coreAddresses[user], "User already has no access");
    coreAddresses[user] = false;
  }

  // Authorized Contracts 
  function authorized(address contractAddress) external view override returns(bool) {
    return authorizedContracts[contractAddress];
  }

  function giveAuthorization(address contractAddress) public onlyOwner {
    require(!authorizedContracts[contractAddress], "Contract is already authorized");
    authorizedContracts[contractAddress] = true;
  }

  function revokeAuthorization(address contractAddress) external onlyOwner {
    require(authorizedContracts[contractAddress], "Contract already is not authorized");
    authorizedContracts[contractAddress] = false;
  }
}