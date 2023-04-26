import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';

pragma solidity ^0.5.10;

contract ExampleUsdcCoin is ERC20 {
  string public name = "ExampleUsdcCoin"; 
  string public symbol = "USDC";
  uint public decimals = 6;

  constructor () public {
    _mint(msg.sender, 82020000000000000000000);
  }
}