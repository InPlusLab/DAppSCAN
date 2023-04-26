// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract ClaimableUpgradeable is Initializable, ContextUpgradeable {
  address private _owner;
  address public pendingOwner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event NewPendingOwner(address indexed owner);

  function __Climable_init() internal initializer {
    __Context_init_unchained();
    __Climable_init_unchained();
  }

  function __Climable_init_unchained() internal initializer {
    address msgSender = _msgSender();
    _owner = msgSender;
    emit OwnershipTransferred(address(0), msgSender);
  }

  function owner() public view virtual returns (address) {
    return _owner;
  }

  modifier onlyOwner() {
    require(_msgSender() == owner(), "Ownable: caller is not the owner");
    _;
  }

  modifier onlyPendingOwner() {
    require(_msgSender() == pendingOwner);
    _;
  }

  function renounceOwnership() public virtual onlyOwner {
    emit OwnershipTransferred(owner(), address(0));
    _owner = address(0);
  }

  function transferOwnership(address newOwner) public virtual onlyOwner {
    require(pendingOwner == address(0));
    pendingOwner = newOwner;
    emit NewPendingOwner(newOwner);
  }

  function cancelTransferOwnership() public onlyOwner {
    require(pendingOwner != address(0));
    delete pendingOwner;
    emit NewPendingOwner(address(0));
  }

  function claimOwnership() public onlyPendingOwner {
    emit OwnershipTransferred(owner(), pendingOwner);
    _owner = pendingOwner;
    delete pendingOwner;
  }
}
