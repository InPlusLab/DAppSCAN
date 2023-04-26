pragma solidity >=0.4.21 <0.6.0;

import "../AddressList.sol";

contract TestAddressList is AddressList{
  function add_address(address addr) public{
    _add_address(addr);
  }

  function remove_address(address addr) public{
    _remove_address(addr);
  }

  function reset() public{
  	_reset();
  }
}
