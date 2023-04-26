//// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Whitelist is Ownable {

 // 1 => whitelisted; 0 => NOT whitelisted
  mapping (address => uint8) public whitelistedMap;

 // true => whitelist is activated; false => whitelist is deactivated
  bool public whitelistStatus;

  event WhitelistStatusChanged(bool Status);

  constructor() public{
    whitelistStatus = true;
  }

  modifier Whitelisted() {
    require(whitelistedMap[msg.sender] == 1 || whitelistStatus == false, "You are not whitelisted");
  _;}

  function whitelistAddress(address[] calldata addressList)
    public
    onlyOwner
  {
    for (uint j = 0; j < addressList.length; ++j)
    {
    whitelistedMap[addressList[j]] = 1;
    }
  }

  function blacklistAddress(address[] calldata addressList)
    public
    onlyOwner
  {
    for (uint j = 0; j < addressList.length; ++j)
    {
    whitelistedMap[addressList[j]] = 0;
    }
  }

  function changeWhitelistStatus()
    public
    onlyOwner
  {
    if (whitelistStatus == true){
      whitelistStatus = false;
      emit WhitelistStatusChanged(false);
    }else{
      whitelistStatus = true;
      emit WhitelistStatusChanged(true);
    }
  }
}
  