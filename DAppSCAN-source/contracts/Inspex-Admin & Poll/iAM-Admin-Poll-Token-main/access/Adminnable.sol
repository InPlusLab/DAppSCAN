// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import '../interfaces/IAdminManage.sol';

abstract contract Adminnable {
  IAdminManage internal adminManage;

  constructor(IAdminManage _adminManage) {
    adminManage = _adminManage;
  }

  modifier onlyAdmin() {
    bool isAdmin = adminManage.isAdmin(msg.sender);
    require(isAdmin, 'Adminnable: caller is not the admin');
    _;
  }

  function getAdminManage() public view returns (address) {
    return address(adminManage);
  }

  function admin(address _address) public view returns (bool) {
    return adminManage.isAdmin(_address);
  }
}
