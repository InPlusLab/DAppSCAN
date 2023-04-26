pragma solidity ^0.4.23;

import '../../core/Contract.sol';

library Provider {

  using Contract for *;

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
}
