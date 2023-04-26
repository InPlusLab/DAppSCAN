pragma solidity >=0.8.0 <0.9.0;

import "truffle/Assert.sol";
import "../contracts/CheckDot.sol";

contract TestCheckDotAsset {


  function testInitialBalanceWithNewAsset() public {
    CheckDot meta = new CheckDot(msg.sender);

    uint expected = 10000000 * (10 ** 18);
    Assert.equal(meta.balanceOf(msg.sender), expected, "CheckDot Token deployer should have 10M initially");
  }

}
