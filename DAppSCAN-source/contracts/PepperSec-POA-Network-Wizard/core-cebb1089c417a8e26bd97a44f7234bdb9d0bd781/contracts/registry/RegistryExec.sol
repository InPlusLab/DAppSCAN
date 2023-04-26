pragma solidity ^0.4.23;

import '../core/ScriptExec.sol';

contract RegistryExec is ScriptExec {

  struct Registry {
    address index;
    address implementation;
  }

  // Maps execution ids to its registry app metadata
  mapping (bytes32 => Registry) public registry_instance_info;
  // Maps address to list of deployed Registry instances
  mapping (address => Registry[]) public deployed_registry_instances;

  /// EVENTS ///

  event RegistryInstanceCreated(address indexed creator, bytes32 indexed execution_id, address index, address implementation);

  /// REGISTRY FUNCTIONS ///

  /*
  Creates an instance of a registry application and returns its execution id
  @param _index: The index file of the registry app (holds getters and init functions)
  @param _implementation: The file implementing the registry's functionality
  @return exec_id: The execution id under which the registry will store data
  */
  function createRegistryInstance(address _index, address _implementation) external onlyAdmin() returns (bytes32 exec_id) {
    // Validate input -
    require(_index != 0 && _implementation != 0, 'Invalid input');

    // Creates a registry from storage and returns the registry exec id -
    exec_id = StorageInterface(app_storage).createRegistry(_index, _implementation);

    // Ensure a valid execution id returned from storage -
    require(exec_id != 0, 'Invalid response from storage');

    // If there is not already a default registry exec id set, set it
    if (registry_exec_id == 0)
      registry_exec_id = exec_id;

    // Create Registry struct in memory -
    Registry memory reg = Registry(_index, _implementation);

    // Set various app metadata values -
    deployed_by[exec_id] = msg.sender;
    registry_instance_info[exec_id] = reg;
    deployed_registry_instances[msg.sender].push(reg);
    // Emit event -
    emit RegistryInstanceCreated(msg.sender, exec_id, _index, _implementation);
  }

  /*
  Registers an application as the admin under the provider and registry exec id
  @param _app_name: The name of the application to register
  @param _index: The index file of the application - holds the getters and init functions
  @param _selectors: The selectors of the functions which the app implements
  @param _implementations: The addresses at which each function is located
  */
  function registerApp(bytes32 _app_name, address _index, bytes4[] _selectors, address[] _implementations) external onlyAdmin() {
    // Validate input
    require(_app_name != 0 && _index != 0, 'Invalid input');
    require(_selectors.length == _implementations.length && _selectors.length != 0, 'Invalid input');
    // Check contract variables for valid initialization
    require(app_storage != 0 && registry_exec_id != 0 && provider != 0, 'Invalid state');

    // Execute registerApp through AbstractStorage -
    uint emitted;
    uint paid;
    uint stored;
    (emitted, paid, stored) = StorageInterface(app_storage).exec(msg.sender, registry_exec_id, msg.data);

    // Ensure zero values for emitted and paid, and nonzero value for stored -
    require(emitted == 0 && paid == 0 && stored != 0, 'Invalid state change');
  }

  /*
  Registers a version of an application as the admin under the provider and registry exec id
  @param _app_name: The name of the application under which the version will be registered
  @param _version_name: The name of the version to register
  @param _index: The index file of the application - holds the getters and init functions
  @param _selectors: The selectors of the functions which the app implements
  @param _implementations: The addresses at which each function is located
  */
  function registerAppVersion(bytes32 _app_name, bytes32 _version_name, address _index, bytes4[] _selectors, address[] _implementations) external onlyAdmin() {
    // Validate input
    require(_app_name != 0 && _version_name != 0 && _index != 0, 'Invalid input');
    require(_selectors.length == _implementations.length && _selectors.length != 0, 'Invalid input');
    // Check contract variables for valid initialization
    require(app_storage != 0 && registry_exec_id != 0 && provider != 0, 'Invalid state');

    // Execute registerApp through AbstractStorage -
    uint emitted;
    uint paid;
    uint stored;
    (emitted, paid, stored) = StorageInterface(app_storage).exec(msg.sender, registry_exec_id, msg.data);

    // Ensure zero values for emitted and paid, and nonzero value for stored -
    require(emitted == 0 && paid == 0 && stored != 0, 'Invalid state change');
  }
}
