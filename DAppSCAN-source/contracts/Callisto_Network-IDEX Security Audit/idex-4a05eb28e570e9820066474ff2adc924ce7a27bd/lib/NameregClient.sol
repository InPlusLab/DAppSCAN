pragma solidity ^0.4.6;
import "./TrustClient.sol";
import "./Namereg.sol";

contract NameregClient is TrustClient {
  address public nameregAddress;
  function setNameregOwner(address addr) external setter onlyOwnerUnlocked returns (bool success) {
    nameregAddress = addr;
  }
  function setNamereg(address addr) external multisig(sha3(msg.data)) returns (bool success) {
    nameregAddress = addr;
  }
  function resolve(bytes32 name) constant internal returns (address record) {
    return Namereg(nameregAddress).resolve(name);
  }
}
