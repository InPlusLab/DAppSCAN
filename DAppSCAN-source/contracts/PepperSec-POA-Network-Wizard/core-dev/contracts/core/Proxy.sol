pragma solidity ^0.4.23;

import '../interfaces/StorageInterface.sol';

contract Proxy {

  // Registry storage
  address public proxy_admin;
  StorageInterface public app_storage;
  bytes32 public registry_exec_id;
  address public provider;
  bytes32 public app_name;

  // App storage
  bytes32 public app_version;
  bytes32 public app_exec_id;
  address public app_index;

  // Function selector for storage 'exec' function
  bytes4 internal constant EXEC_SEL = bytes4(keccak256('exec(address,bytes32,bytes)'));

  // Event emitted in case of a revert from storage
  event StorageException(bytes32 indexed execution_id, string message);

  // For storage refunds
  function () external payable {
    require(msg.sender == address(app_storage));
  }

  // Constructor - sets proxy admin, as well as initial variables
  constructor (address _storage, bytes32 _registry_exec_id, address _provider, bytes32 _app_name) public {
    proxy_admin = msg.sender;
    app_storage = StorageInterface(_storage);
    registry_exec_id = _registry_exec_id;
    provider = _provider;
    app_name = _app_name;
  }

  // Declare abstract execution function -
  function exec(bytes _calldata) external payable returns (bool);

  // Checks to see if an error message was returned with the failed call, and emits it if so -
  function checkErrors() internal {
    // If the returned data begins with selector 'Error(string)', get the contained message -
    string memory message;
    bytes4 err_sel = bytes4(keccak256('Error(string)'));
    assembly {
      // Get pointer to free memory, place returned data at pointer, and update free memory pointer
      let ptr := mload(0x40)
      returndatacopy(ptr, 0, returndatasize)
      mstore(0x40, add(ptr, returndatasize))

      // Check value at pointer for equality with Error selector -
      if eq(mload(ptr), and(err_sel, 0xffffffff00000000000000000000000000000000000000000000000000000000)) {
        message := add(0x24, ptr)
      }
    }
    // If no returned message exists, emit a default error message. Otherwise, emit the error message
    if (bytes(message).length == 0)
      emit StorageException(app_exec_id, "No error recieved");
    else
      emit StorageException(app_exec_id, message);
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
}
