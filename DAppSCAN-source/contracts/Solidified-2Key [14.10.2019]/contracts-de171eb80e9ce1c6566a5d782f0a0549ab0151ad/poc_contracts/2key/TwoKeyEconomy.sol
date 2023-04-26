pragma solidity ^0.4.24;

import '../../contracts/openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol';
import '../../contracts/openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import '../../contracts/openzeppelin-solidity/contracts/ownership/Ownable.sol';


contract TwoKeyEconomy is StandardToken, Ownable {
  string public name = 'TwoKeyEconomy';
  string public symbol = '2Key';
  uint8 public decimals = 18;
//  uint256 private totalSupply_ = 1000000000000000000000000000;

  constructor() Ownable() public {
    totalSupply_ = 1000000000000000000000000000;
    balances[msg.sender] = totalSupply_;
  }

  function transferFrom(
    address _from,
    address _to,
    uint256 _value
  )
  public
  returns (bool)
  {
    require(_value <= balances[_from]);
//    require(_value <= allowed[_from][msg.sender]);
    require(_to != address(0));

    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
//    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    emit Transfer(_from, _to, _value);
    return true;
  }

}
