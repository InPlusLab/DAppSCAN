pragma solidity ^0.4.23;

import '../../core/Contract.sol';

library Provider {

  using Contract for *;

  // Returns the index address for this exec id
  function appIndex() internal pure returns (bytes32)
    { return keccak256('index'); }

  // Storage seed for a script executor's execution permission mapping
  function execPermissions(address _exec) internal pure returns (bytes32)
    { return keccak256(_exec, keccak256('script_exec_permissions')); }

  // Storage seed for a function selector's implementation address
  function appSelectors(bytes4 _selector) internal pure returns (bytes32)
    { return keccak256(_selector, 'implementation'); }

  // Returns the location of a provider's list of registered applications in storage
  function registeredApps() internal pure returns (bytes32)
    { return keccak256(bytes32(Contract.sender()), 'app_list'); }

  // Returns the location of a registered app's name under a provider
  function appBase(bytes32 _app) internal pure returns (bytes32)
    { return keccak256(_app, keccak256(bytes32(Contract.sender()), 'app_base')); }

  // Returns the location of an app's list of versions
  function appVersionList(bytes32 _app) internal pure returns (bytes32)
    { return keccak256('versions', appBase(_app)); }

  // Returns the location of a version's name
  function versionBase(bytes32 _app, bytes32 _version) internal pure returns (bytes32)
    { return keccak256(_version, 'version', appBase(_app)); }

  // Returns the location of a registered app's index address under a provider
  function versionIndex(bytes32 _app, bytes32 _version) internal pure returns (bytes32)
    { return keccak256('index', versionBase(_app, _version)); }

  // Returns the location of an app's function selectors, registered under a provider
  function versionSelectors(bytes32 _app, bytes32 _version) internal pure returns (bytes32)
    { return keccak256('selectors', versionBase(_app, _version)); }

  // Returns the location of an app's implementing addresses, registered under a provider
  function versionAddresses(bytes32 _app, bytes32 _version) internal pure returns (bytes32)
    { return keccak256('addresses', versionBase(_app, _version)); }

  // Returns the location of the version before the current version
  function previousVersion(bytes32 _app, bytes32 _version) internal pure returns (bytes32)
    { return keccak256("previous version", versionBase(_app, _version)); }

  // Returns storage location of appversion list at a specific index
  function appVersionListAt(bytes32 _app, uint _index) internal pure returns (bytes32)
    { return bytes32((32 * _index) + uint(appVersionList(_app))); }

  // Registers an application under a given name for the sender
  function registerApp(bytes32 _app, address _index, bytes4[] _selectors, address[] _implementations) external view {
    // Begin execution -
    Contract.authorize(msg.sender);

    // Throw if the name has already been registered
    if (Contract.read(appBase(_app)) != bytes32(0))
      revert("app is already registered");

    if (_selectors.length != _implementations.length || _selectors.length == 0)
      revert("invalid input arrays");

    // Start storing values
    Contract.storing();

    // Store the app name in the list of registered app names
    uint num_registered_apps = uint(Contract.read(registeredApps()));

    Contract.increase(registeredApps()).by(uint(1));

    Contract.set(
      bytes32(32 * (num_registered_apps + 1) + uint(registeredApps()))
    ).to(_app);

    // Store the app name at app_base
    Contract.set(appBase(_app)).to(_app);

    // Set the first version to this app
    Contract.set(versionBase(_app, _app)).to(_app);

    // Push the app to its own version list as the first version
    Contract.set(appVersionList(_app)).to(uint(1));

    Contract.set(
      bytes32(32 + uint(appVersionList(_app)))
    ).to(_app);

    // Sets app index
    Contract.set(versionIndex(_app, _app)).to(_index);

    // Loop over the passed-in selectors and addresses and store them each at
    // version_selectors/version_addresses, respectively
    Contract.set(versionSelectors(_app, _app)).to(_selectors.length);
    Contract.set(versionAddresses(_app, _app)).to(_implementations.length);
    for (uint i = 0; i < _selectors.length; i++) {
      Contract.set(bytes32(32 * (i + 1) + uint(versionSelectors(_app, _app)))).to(_selectors[i]);
      Contract.set(bytes32(32 * (i + 1) + uint(versionAddresses(_app, _app)))).to(_implementations[i]);
    }

    // Set previous version to 0
    Contract.set(previousVersion(_app, _app)).to(uint(0));

    // End execution and commit state changes to storage -
    Contract.commit();
  }

  function registerAppVersion(bytes32 _app, bytes32 _version, address _index, bytes4[] _selectors, address[] _implementations) external view {
    // Begin execution -
    Contract.authorize(msg.sender);

    // Throw if the app has not been registered
    // Throw if the version has already been registered (check app_base)
    if (Contract.read(appBase(_app)) == bytes32(0))
      revert("App has not been registered");

    if (Contract.read(versionBase(_app, _version)) != bytes32(0))
      revert("Version already exists");

    if (
      _selectors.length != _implementations.length ||
      _selectors.length == 0
    ) revert("Invalid input array lengths");

    // Begin storing values
    Contract.storing();

    // Store the version name at version_base
    Contract.set(versionBase(_app, _version)).to(_version);

    // Push the version to the app's version list
    uint num_versions = uint(Contract.read(appVersionList(_app)));
    Contract.set(appVersionListAt(_app, (num_versions + 1))).to(_version);
    Contract.set(appVersionList(_app)).to(num_versions + 1);

    // Store the index at version_index
    Contract.set(versionIndex(_app, _version)).to(_index);

    // Loop over the passed-in selectors and addresses and store them each at
    // version_selectors/version_addresses, respectively
    Contract.set(versionSelectors(_app, _version)).to(_selectors.length);
    Contract.set(versionAddresses(_app, _version)).to(_implementations.length);
    for (uint i = 0; i < _selectors.length; i++) {
      Contract.set(bytes32(32 * (i + 1) + uint(versionSelectors(_app, _version)))).to(_selectors[i]);
      Contract.set(bytes32(32 * (i + 1) + uint(versionAddresses(_app, _version)))).to(_implementations[i]);
    }

    // Set the version's previous version
    bytes32 prev_version = Contract.read(bytes32(32 * num_versions + uint(appVersionList(_app))));
    Contract.set(previousVersion(_app, _version)).to(prev_version);

    // End execution and commit state changes to storage -
    Contract.commit();
  }

  /*
  Updates an application to the latest version -

  @param _provider: The provider of the application
  @param _app_name: The name of the application
  @param _current_version: The current version of the application
  @param _registry_id: The exec id of the registry of the application
  */
  function updateInstance(bytes32 _app_name, bytes32 _current_version, bytes32 _registry_id) external view {
    // Begin execution -
    Contract.authorize(msg.sender);

    // Validate input -
    require(_app_name != 0 && _current_version != 0 && _registry_id != 0, 'invalid input');

    // Get current version selectors and ensure nonzero length -
    bytes4[] memory current_selectors = getVersionSelectors(_app_name, _current_version, _registry_id);
    require(current_selectors.length != 0, 'invalid current version');

    // Get latest version name and ensure it is not the current version, or zero -
    bytes32 latest_version = getLatestVersion(_app_name, _registry_id);
    require(latest_version != _current_version, 'current version is already latest');
    require(latest_version != 0, 'invalid latest version');

    // Get latest version index, selectors, and implementing addresses.
    // Ensure all returned values are valid -
    address latest_idx = getVersionIndex(_app_name, latest_version, _registry_id);
    bytes4[] memory latest_selectors = getVersionSelectors(_app_name, latest_version, _registry_id);
    address[] memory latest_impl = getVersionImplementations(_app_name, latest_version, _registry_id);
    require(latest_idx != 0, 'invalid version idx address');
    require(latest_selectors.length != 0 && latest_selectors.length == latest_impl.length, 'invalid implementation specification');

    // Set up a storage buffer to clear current version implementation -
    Contract.storing();

    // For each selector, set its implementation to 0
    for (uint i = 0; i < current_selectors.length; i++)
      Contract.set(appSelectors(current_selectors[i])).to(address(0));

    // Set this application's index address to equal the latest version's index -
    Contract.set(appIndex()).to(latest_idx);

    // Loop over implementing addresses, and map each function selector to its corresponding address for the new instance
    for (i = 0; i < latest_selectors.length; i++) {
      require(latest_selectors[i] != 0 && latest_impl[i] != 0, 'invalid input - expected nonzero implementation');
      Contract.set(appSelectors(latest_selectors[i])).to(latest_impl[i]);
    }

    // Commit the changes to the storage contract
    Contract.commit();
  }

  /*
  Replaces the script exec address with a new address

  @param _new_exec_addr: The address that will be granted permissions
  */
  function updateExec(address _new_exec_addr) external view {
    // Authorize the sender and set up the run-time memory of this application
    Contract.authorize(msg.sender);

    // Validate input -
    require(_new_exec_addr != 0, 'invalid replacement');

    // Set up a storage buffer -
    Contract.storing();

    // Remove current permissions -
    Contract.set(execPermissions(msg.sender)).to(false);

    // Add updated permissions for the new address -
    Contract.set(execPermissions(_new_exec_addr)).to(true);

    // Commit the changes to the storage contract
    Contract.commit();
  }

  /// Helpers ///

  function registryRead(bytes32 _location, bytes32 _registry_id) internal view returns (bytes32 value) {
    _location = keccak256(_location, _registry_id);
    assembly { value := sload(_location) }
  }

  /// Registry Getters ///

  /*
  Returns name of the latest version of an application

  @param _app: The name of the application
  @param _registry_id: The exec id of the registry application
  @return bytes32: The latest version of the application
  */
  function getLatestVersion(bytes32 _app, bytes32 _registry_id) internal view returns (bytes32) {
    uint length = uint(registryRead(appVersionList(_app), _registry_id));
    // Return the latest version of this application
    return registryRead(appVersionListAt(_app, length), _registry_id);
  }

  /*
  Returns the index address of an app version

  @param _app: The name of the application
  @param _version: The name of the version
  @param _registry_id: The exec id of the registry application
  @return address: The index address of this version
  */
  function getVersionIndex(bytes32 _app, bytes32 _version, bytes32 _registry_id) internal view returns (address) {
    return address(registryRead(versionIndex(_app, _version), _registry_id));
  }

  /*
  Returns the addresses associated with this version's implementation

  @param _app: The name of the application
  @param _version: The name of the version
  @param _registry_id: The exec id of the registry application
  @return impl: An address array containing all of this version's implementing addresses
  */
  function getVersionImplementations(bytes32 _app, bytes32 _version, bytes32 _registry_id) internal view returns (address[] memory impl) {
    // Get number of addresses
    uint length = uint(registryRead(versionAddresses(_app, _version), _registry_id));
    // Allocate space for return
    impl = new address[](length);
    // For each address, read it from storage and add it to the array
    for (uint i = 0; i < length; i++) {
      bytes32 location = bytes32(32 * (i + 1) + uint(versionAddresses(_app, _version)));
      impl[i] = address(registryRead(location, _registry_id));
    }
  }

  /*
  Returns the function selectors associated with this version's implementation

  @param _app: The name of the application
  @param _version: The name of the version
  @param _registry_id: The exec id of the registry application
  @return sels: A bytes4 array containing all of this version's function selectors
  */
  function getVersionSelectors(bytes32 _app, bytes32 _version, bytes32 _registry_id) internal view returns (bytes4[] memory sels) {
    // Get number of addresses
    uint length = uint(registryRead(versionSelectors(_app, _version), _registry_id));
    // Allocate space for return
    sels = new bytes4[](length);
    // For each address, read it from storage and add it to the array
    for (uint i = 0; i < length; i++) {
      bytes32 location = bytes32(32 * (i + 1) + uint(versionSelectors(_app, _version)));
      sels[i] = bytes4(registryRead(location, _registry_id));
    }
  }

}
