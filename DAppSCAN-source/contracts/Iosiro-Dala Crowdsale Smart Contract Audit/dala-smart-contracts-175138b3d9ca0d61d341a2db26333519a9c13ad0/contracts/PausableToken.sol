pragma solidity ^0.4.15;

import './StandardToken.sol';
import 'zeppelin-solidity/contracts/lifecycle/Pausable.sol';

/**
 * Pausable token
 *
 * Simple ERC20 Token example, with pausable token creation
 **/

contract PausableToken is StandardToken, Pausable {
  // SWC-100-Function Default Visibility: L14-L16
  function transfer(address _to, uint _value) whenNotPaused returns (bool) {
    return super.transfer(_to, _value);
  }
  // SWC-100-Function Default Visibility: L18-L20
  function transferFrom(address _from, address _to, uint _value) whenNotPaused returns (bool) {
    return super.transferFrom(_from, _to, _value);
  }
}
