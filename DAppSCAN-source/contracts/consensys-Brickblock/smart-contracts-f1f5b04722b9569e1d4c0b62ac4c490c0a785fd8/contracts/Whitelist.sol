pragma solidity 0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";


contract Whitelist is Ownable {
  uint8 public constant version = 1;

  mapping (address => bool) public whitelisted;

  event WhitelistedEvent(address indexed account, bool isWhitelisted);

  function addAddress(address _address)
    public
    onlyOwner
  {
    require(whitelisted[_address] != true);
    whitelisted[_address] = true;
    emit WhitelistedEvent(_address, true);
  }

  function removeAddress(address _address)
    public
    onlyOwner
  {
    require(whitelisted[_address] != false);
    whitelisted[_address] = false;
    emit WhitelistedEvent(_address, false);
  }

  // prevent anyone from sending funds other than selfdestructs of course :)
  function()
    public
    payable
  {
    revert();
  }
}
