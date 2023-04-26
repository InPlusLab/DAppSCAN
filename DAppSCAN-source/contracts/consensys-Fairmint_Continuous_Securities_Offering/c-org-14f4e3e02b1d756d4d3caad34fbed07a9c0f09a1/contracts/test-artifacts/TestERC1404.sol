pragma solidity ^0.5.0;


contract TestERC1404
{
  uint8 public restriction;
  mapping(address => bool) public alwaysApproved;

  function detectTransferRestriction(
    address _from,
    address _to,
    uint256 //_value
  ) public
    returns(uint8)
  {
    if(alwaysApproved[_from] || alwaysApproved[_to]) return 0;
    return restriction;
  }

  function messageForTransferRestriction(
    uint8 _restrictionCode
  ) public pure
    returns(string memory)
  {
    if(_restrictionCode == 0)
    {
      return "SUCCESS";
    }
    else if(_restrictionCode == 1)
    {
      return "DENIED";
    }
    return "UNKNOWN_ERROR";
  }

  function updateRestriction(
    uint8 _restriction
  ) public
  {
    restriction = _restriction;
  }

  function approve(
    address _alwaysApprovedAccount
  ) public
  {
    alwaysApproved[_alwaysApprovedAccount] = true;
  }
}