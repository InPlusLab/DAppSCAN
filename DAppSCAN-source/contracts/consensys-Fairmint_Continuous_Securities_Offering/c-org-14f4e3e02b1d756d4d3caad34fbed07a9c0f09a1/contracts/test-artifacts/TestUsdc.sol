pragma solidity ^0.5.0;

import "./MintableERC20.sol";


contract TestUsdc is
  MintableERC20
{
  constructor() public
    MintableERC20("Test USDC token", "USDC", 6)
  {}
}
