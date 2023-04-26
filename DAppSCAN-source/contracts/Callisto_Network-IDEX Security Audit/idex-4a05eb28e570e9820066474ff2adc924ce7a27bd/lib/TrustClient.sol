pragma solidity ^0.4.6;
import "../Trust.sol";
import "./Assertive.sol";
import "./StateTransferrable.sol";

contract TrustClient is StateTransferrable, TrustEvents {

  address public trustAddress;

  modifier multisig (bytes32 hash) {
    assert(trustAddress != address(0x0));
    address current = Trust(trustAddress).functionCalls(uint256(hash));
    uint8 code = Trust(trustAddress).authCall(msg.sender, hash);
    if (code == 0) Unauthorized(msg.sender);
    else if (code == 1) AuthInit(msg.sender);
    else if (code == 2) {
      AuthComplete(current, msg.sender);
      _;
    }
    else if (code == 3) {
      AuthPending(msg.sender);
    }
  }
  
  function setTrust(address addr) setter onlyOwnerUnlocked {
    trustAddress = addr;
  }

  function cancel() returns (uint8 status) {
    assert(trustAddress != address(0x0));
    uint8 code = Trust(trustAddress).authCancel(msg.sender);
    if (code == 0) Unauthorized(msg.sender);
    else if (code == 1) NothingToCancel(msg.sender);
    else if (code == 2) AuthCancel(msg.sender, msg.sender);
    return code;
  }

}
