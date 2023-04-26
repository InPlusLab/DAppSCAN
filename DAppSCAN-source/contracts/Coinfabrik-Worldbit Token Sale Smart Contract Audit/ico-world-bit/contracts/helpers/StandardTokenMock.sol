pragma solidity ^0.4.15;

import '../StandardToken.sol';

// Mock class for StandardToken contract
contract StandardTokenMock is StandardToken {
  function mint(address receiver, uint amount) public {
    mintInternal(receiver, amount);
  }
  
  /**
   * Made public for abvailability in tests
   */
  function burnTokensMock(address account, uint value) public {
    super.burnTokens(account, value);
  }
}