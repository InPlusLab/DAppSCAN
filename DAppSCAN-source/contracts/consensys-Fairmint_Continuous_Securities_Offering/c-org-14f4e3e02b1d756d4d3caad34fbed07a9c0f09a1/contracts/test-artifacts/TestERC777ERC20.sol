pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC777/ERC777.sol";


contract TestERC777ERC20 is
  Ownable,
  ERC777
{
  constructor() public ERC777("ZOS ERC777", "Z77", new address[](0)) {}

  function mint(address _tokenHolder, uint _amount) public onlyOwner {
    _mint(msg.sender, _tokenHolder, _amount, "", "");
  }
}
