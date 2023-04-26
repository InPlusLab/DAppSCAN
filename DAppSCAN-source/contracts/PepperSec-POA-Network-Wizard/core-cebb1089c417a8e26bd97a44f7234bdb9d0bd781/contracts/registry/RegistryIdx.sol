pragma solidity ^0.4.23;

import '../core/Contract.sol';
import '../interfaces/GetterInterface.sol';
import '../lib/ArrayUtils.sol';

library RegistryIdx {

  using Contract for *;
  using ArrayUtils for bytes32[];

  bytes32 internal constant EXEC_PERMISSIONS = keccak256('script_exec_permissions');

  // Returns the storage location of a script execution address's permissions -
  function execPermissions(address _exec) internal pure returns (bytes32)
    { return keccak256(_exec, EXEC_PERMISSIONS); }

  // Simple init function - sets the sender as a script executor for this instance
  function init() external view {
    // Begin execution - we are initializing an instance of this application
    Contract.initialize();
    // Begin storing init information -
    Contract.storing();
    // Authorize sender as an executor for this instance -
    Contract.set(execPermissions(msg.sender)).to(true);
    // Finish storing and commit authorized sender to storage -
    Contract.commit();
  }

  // Returns the location of a provider's list of registered applications in storage
  function registeredApps(address _provider) internal pure returns (bytes32)
    { return keccak256(bytes32(_provider), 'app_list'); }

  // Returns the location of a registered app's name under a provider
  function appBase(bytes32 _app, address _provider) internal pure returns (bytes32)
    { return keccak256(_app, keccak256(bytes32(_provider), 'app_base')); }

  // Returns the location of an app's list of versions
  function appVersionList(bytes32 _app, address _provider) internal pure returns (bytes32)
    { return keccak256('versions', appBase(_app, _provider)); }

  // Returns the location of a version's name
  function versionBase(bytes32 _app, bytes32 _version, address _provider) internal pure returns (bytes32)
    { return keccak256(_version, 'version', appBase(_app, _provider)); }

  // Returns the location of a registered app's index address under a provider
  function versionIndex(bytes32 _app, bytes32 _version, address _provider) internal pure returns (bytes32)
    { return keccak256('index', versionBase(_app, _version, _provider)); }

  // Returns the location of an app's function selectors, registered under a provider
  function versionSelectors(bytes32 _app, bytes32 _version, address _provider) internal pure returns (bytes32)
    { return keccak256('selectors', versionBase(_app, _version, _provider)); }

  // Returns the location of an app's implementing addresses, registered under a provider
  function versionAddresses(bytes32 _app, bytes32 _version, address _provider) internal pure returns (bytes32)
    { return keccak256('addresses', versionBase(_app, _version, _provider)); }

  // Return a list of applications registered by the address given
  function getApplications(address _storage, bytes32 _exec_id, address _provider) external view returns (bytes32[] memory) {
    uint seed = uint(registeredApps(_provider));

    GetterInterface target = GetterInterface(_storage);
    uint length = uint(target.read(_exec_id, bytes32(seed)));

    bytes32[] memory arr_indices = new bytes32[](length);
    for (uint i = 1; i <= length; i++)
      arr_indices[i - 1] = bytes32((32 * i) + seed);

    return target.readMulti(_exec_id, arr_indices);
  }

  // Return a list of versions of an app registered by the maker
  function getVersions(address _storage, bytes32 _exec_id, address _provider, bytes32 _app) external view returns (bytes32[] memory) {
    uint seed = uint(appVersionList(_app, _provider));

    GetterInterface target = GetterInterface(_storage);
    uint length = uint(target.read(_exec_id, bytes32(seed)));

    bytes32[] memory arr_indices = new bytes32[](length);
    for (uint i = 1; i <= length; i++)
      arr_indices[i - 1] = bytes32((32 * i) + seed);

    return target.readMulti(_exec_id, arr_indices);
  }

  // Returns the latest version of an application
  function getLatestVersion(address _storage, bytes32 _exec_id, address _provider, bytes32 _app) external view returns (bytes32) {
    uint seed = uint(appVersionList(_app, _provider));

    GetterInterface target = GetterInterface(_storage);
    uint length = uint(target.read(_exec_id, bytes32(seed)));

    seed = (32 * length) + seed;

    return target.read(_exec_id, bytes32(seed));
  }

  // Returns a version's index address, function selectors, and implementing addresses
  function getVersionImplementation(address _storage, bytes32 _exec_id, address _provider, bytes32 _app, bytes32 _version) external view
  returns (address index, bytes4[] memory selectors, address[] memory implementations) {
    uint seed = uint(versionIndex(_app, _version, _provider));

    GetterInterface target = GetterInterface(_storage);
    index = address(target.read(_exec_id, bytes32(seed)));

    seed = uint(versionSelectors(_app, _version, _provider));
    uint length = uint(target.read(_exec_id, bytes32(seed)));

    bytes32[] memory arr_indices = new bytes32[](length);
    for (uint i = 1; i <= length; i++)
      arr_indices[i - 1] = bytes32((32 * i) + seed);

    selectors = target.readMulti(_exec_id, arr_indices).toBytes4Arr();

    seed = uint(versionAddresses(_app, _version, _provider));
    for (i = 1; i <= length; i++)
      arr_indices[i - 1] = bytes32((32 * i) + seed);

    implementations = target.readMulti(_exec_id, arr_indices).toAddressArr();
  }
}
