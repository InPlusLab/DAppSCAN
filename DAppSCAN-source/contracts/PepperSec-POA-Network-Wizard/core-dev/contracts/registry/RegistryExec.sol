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

  /// APPLICATION EXECUTION ///

  bytes4 internal constant EXEC_SEL = bytes4(keccak256('exec(address,bytes32,bytes)'));

  /*
  Executes an application using its execution id and storage address.

  @param _exec_id: The instance exec id, which will route the calldata to the appropriate destination
  @param _calldata: The calldata to forward to the application
  @return success: Whether execution succeeded or not
  */
  function exec(bytes32 _exec_id, bytes _calldata) external payable returns (bool success) {
    // Get function selector from calldata -
    bytes4 sel = getSelector(_calldata);
    // Ensure no registry functions are being called -
    require(
      sel != this.registerApp.selector &&
      sel != this.registerAppVersion.selector &&
      sel != UPDATE_INST_SEL &&
      sel != UPDATE_EXEC_SEL
    );

    // Call 'exec' in AbstractStorage, passing in the sender's address, the app exec id, and the calldata to forward -
    if (address(app_storage).call.value(msg.value)(abi.encodeWithSelector(
      EXEC_SEL, msg.sender, _exec_id, _calldata
    )) == false) {
      // Call failed - emit error message from storage and return 'false'
      checkErrors(_exec_id);
      // Return unspent wei to sender
      address(msg.sender).transfer(address(this).balance);
      return false;
    }

    // Get returned data
    success = checkReturn();
    // If execution failed,
    require(success, 'Execution failed');

    // Transfer any returned wei back to the sender
    address(msg.sender).transfer(address(this).balance);
  }

  // Returns the first 4 bytes of calldata
  function getSelector(bytes memory _calldata) internal pure returns (bytes4 selector) {
    assembly {
      selector := and(
        mload(add(0x20, _calldata)),
        0xffffffff00000000000000000000000000000000000000000000000000000000
      )
    }
  }

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

  // Update instance selectors, index, and addresses
  bytes4 internal constant UPDATE_INST_SEL = bytes4(keccak256('updateInstance(bytes32,bytes32,bytes32)'));

  /*
  Updates an application's implementations, selectors, and index address. Uses default app provider and registry app.
  Uses latest app version by default.

  @param _exec_id: The execution id of the application instance to be updated
  @return success: The success of the call to the application's updateInstance function
  */
  function updateAppInstance(bytes32 _exec_id) external returns (bool success) {
    // Validate input. Only the original deployer can update an application -
    require(_exec_id != 0 && msg.sender == deployed_by[_exec_id], 'invalid sender or input');

    // Get instance metadata from exec id -
    Instance memory inst = instance_info[_exec_id];

    // Call 'exec' in AbstractStorage, passing in the sender's address, the execution id, and
    // the calldata to update the application -
    if(address(app_storage).call(
      abi.encodeWithSelector(EXEC_SEL,            // 'exec' selector
        inst.current_provider,                    // application provider address
        _exec_id,                                 // execution id to update
        abi.encodeWithSelector(UPDATE_INST_SEL,   // calldata for Registry updateInstance function
          inst.app_name,                          // name of the applcation used by the instance
          inst.version_name,                      // name of the current version of the application
          inst.current_registry_exec_id           // registry exec id when the instance was instantiated
        )
      )
    ) == false) {
      // Call failed - emit error message from storage and return 'false'
      checkErrors(_exec_id);
      return false;
    }
    // Check returned data to ensure state was correctly changed in AbstractStorage -
    success = checkReturn();
    // If execution failed, revert state and return an error message -
    require(success, 'Execution failed');

    // If execution was successful, the version was updated. Get the latest version
    // and set the exec id instance info -
    address registry_idx = StorageInterface(app_storage).getIndex(inst.current_registry_exec_id);
    bytes32 latest_version  = RegistryInterface(registry_idx).getLatestVersion(
      app_storage,
      inst.current_registry_exec_id,
      inst.current_provider,
      inst.app_name
    );
    // Ensure nonzero latest version -
    require(latest_version != 0, 'invalid latest version');
    // Set current version -
    instance_info[_exec_id].version_name = latest_version;
  }

  // Update instance script exec contract
  bytes4 internal constant UPDATE_EXEC_SEL = bytes4(keccak256('updateExec(address)'));

  /*
  Updates an application's script executor from this Script Exec to a new address

  @param _exec_id: The execution id of the application instance to be updated
  @param _new_exec_addr: The new script exec address for this exec id
  @returns success: The success of the call to the application's updateExec function
  */
  function updateAppExec(bytes32 _exec_id, address _new_exec_addr) external returns (bool success) {
    // Validate input. Only the original deployer can migrate the script exec address -
    require(_exec_id != 0 && msg.sender == deployed_by[_exec_id] && address(this) != _new_exec_addr && _new_exec_addr != 0, 'invalid input');

    // Call 'exec' in AbstractStorage, passing in the sender's address, the execution id, and
    // the calldata to migrate the script exec address -
    if(address(app_storage).call(
      abi.encodeWithSelector(EXEC_SEL,                            // 'exec' selector
        msg.sender,                                               // sender address
        _exec_id,                                                 // execution id to update
        abi.encodeWithSelector(UPDATE_EXEC_SEL, _new_exec_addr)   // calldata for Registry updateExec
      )
    ) == false) {
      // Call failed - emit error message from storage and return 'false'
      checkErrors(_exec_id);
      return false;
    }
    // Check returned data to ensure state was correctly changed in AbstractStorage -
    success = checkReturn();
    // If execution failed, revert state and return an error message -
    require(success, 'Execution failed');
  }
}
