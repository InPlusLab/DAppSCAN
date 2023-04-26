pragma solidity >=0.4.21 <0.6.0;

import "./utils/AddressArray.sol";

contract AddressList{
  using AddressArray for address[];
  mapping(address => bool) private address_status;
  address[] public addresses;

  constructor() public{}

  function get_all_addresses() public view returns(address[] memory){
    return addresses;
  }

  function get_address(uint i) public view returns(address){
    require(i < addresses.length, "AddressList:get_address, out of range");
    return addresses[i];
  }

  function get_address_num() public view returns(uint){
    return addresses.length;
  }

  function is_address_exist(address addr) public view returns(bool){
    return address_status[addr];
  }

  function _add_address(address addr) internal{
    if(address_status[addr]) return;
    address_status[addr] = true;
    addresses.push(addr);
  }

  function _remove_address(address addr) internal{
    if(!address_status[addr]) return;
    address_status[addr] = false;
    addresses.remove(addr);
  }

  function _reset() internal{
    for(uint i = 0; i < addresses.length; i++){
      address_status[addresses[i]] = false;
    }
    delete addresses;
  }
}

