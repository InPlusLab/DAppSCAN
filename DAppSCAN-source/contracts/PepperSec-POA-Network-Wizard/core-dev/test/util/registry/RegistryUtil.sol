pragma solidity ^0.4.23;

contract RegistryUtil {

  function registerApp(bytes32, address, bytes4[], address[]) public pure returns (bytes memory) {
    return msg.data;
  }

  function registerAppVersion(bytes32, bytes32, address, bytes4[], address[]) public pure returns (bytes memory) {
    return msg.data;
  }
}
