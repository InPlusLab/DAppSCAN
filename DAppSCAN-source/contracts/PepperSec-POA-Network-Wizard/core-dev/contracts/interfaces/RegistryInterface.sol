pragma solidity ^0.4.23;

interface RegistryInterface {
  function getLatestVersion(address stor_addr, bytes32 exec_id, address provider, bytes32 app_name)
      external view returns (bytes32 latest_name);
  function getVersionImplementation(address stor_addr, bytes32 exec_id, address provider, bytes32 app_name, bytes32 version_name)
      external view returns (address index, bytes4[] selectors, address[] implementations);
}
