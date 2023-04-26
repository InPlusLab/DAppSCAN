pragma solidity ^0.5.0;

import "./MintableERC20.sol";


contract TestDai is
  MintableERC20
{
  constructor() public
    MintableERC20("Test DAI token", "DAI", 18)
  {}
}
