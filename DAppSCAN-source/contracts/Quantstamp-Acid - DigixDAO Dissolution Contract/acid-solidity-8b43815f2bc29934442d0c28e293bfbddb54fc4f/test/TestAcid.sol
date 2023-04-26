pragma solidity ^0.5.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/Acid.sol";

contract TestAcid {

  function testInitializationAfterDeployment() public {
    Acid acid = Acid(DeployedAddresses.Acid());

    bool expected = false;

    Assert.equal(acid.isInitialized(), expected, "Contract should not be initialized after deployment.");
  }

  function testOwnerAfterDeployment() public {
    Acid acid = Acid(DeployedAddresses.Acid());
    address expected = msg.sender;
    Assert.equal(acid.owner(), expected, "Owner should be deployer of contract");
  }

  function testDGDTokenContractAfterDeployment() public {
    Acid acid = Acid(DeployedAddresses.Acid());
    address expected = 0x0000000000000000000000000000000000000000;
    Assert.equal(acid.dgdTokenContract(), expected, "dgdTokenContract should be 0x0000000000000000000000000000000000000000 after deployment");
  }

  function testWeiPerNanoDGDAfterDeployment() public {
    Acid acid = Acid(DeployedAddresses.Acid());
    uint256 expected = 0;
    Assert.equal(acid.weiPerNanoDGD(), expected, "weiPerNanoDGD should be 0 after deployment");
  }

}
