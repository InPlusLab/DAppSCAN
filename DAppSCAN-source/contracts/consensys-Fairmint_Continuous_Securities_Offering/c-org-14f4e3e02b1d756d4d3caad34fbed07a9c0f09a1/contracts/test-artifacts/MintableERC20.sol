pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";


contract MintableERC20 is
  ERC20,
  ERC20Detailed
{
  constructor(string memory _name, string memory _symbol, uint8 _decimals) public
    ERC20Detailed(_name, _symbol, _decimals)
  {}

  function mint(address _account, uint256 _amount) public returns (bool) {
    // Stop excessive amounts so we don't overflow
    require(_amount < 1000000000000000000000000000000, "LOWER_AMOUNT");
    _mint(_account, _amount);
    return true;
  }
}
