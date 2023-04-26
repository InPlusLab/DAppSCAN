pragma solidity 0.4.23;


contract PoaProxy {
  uint8 public constant version = 1;
  bytes32 public constant proxyMasterContractSlot = keccak256("masterAddress");
  bytes32 public constant proxyRegistrySlot = keccak256("registry");

  event ProxyUpgradedEvent(address upgradedFrom, address upgradedTo);

  constructor(
    address _master,
    address _registry
  )
    public
  {
    require(_master != address(0));
    require(_registry != address(0));
    bytes32 _proxyMasterContractSlot = proxyMasterContractSlot;
    bytes32 _proxyRegistrySlot = proxyRegistrySlot;

    // all storage locations are pre-calculated using hashes of names
    assembly {
      sstore(_proxyMasterContractSlot, _master) // store master address in master slot
      sstore(_proxyRegistrySlot, _registry) // store registry address in registry slot
    }
  }

  //
  // proxy state getters
  //

  function proxyMasterContract()
    public
    view
    returns (address _masterContract)
  {
    bytes32 _proxyMasterContractSlot = proxyMasterContractSlot;
    assembly {
      _masterContract := sload(_proxyMasterContractSlot)
    }
  }

  function proxyRegistry()
    public
    view
    returns (address _proxyRegistry)
  {
    bytes32 _proxyRegistrySlot = proxyRegistrySlot;
    assembly {
      _proxyRegistry := sload(_proxyRegistrySlot)
    }
  }

  //
  // proxy state helpers
  //

  function getContractAddress(
    string _name
  )
    public
    view
    returns (address _contractAddress)
  {
    bytes4 _sig = bytes4(keccak256("getContractAddress32(bytes32)"));
    bytes32 _name32 = keccak256(_name);
    bytes32 _proxyRegistrySlot = proxyRegistrySlot;

    assembly {
      let _call := mload(0x40)          // set _call to free memory pointer
      mstore(_call, _sig)               // store _sig at _call pointer
      mstore(add(_call, 0x04), _name32) // store _name32 at _call offset by 4 bytes for pre-existing _sig

      // staticcall(g, a, in, insize, out, outsize) => 0 on error 1 on success
      let success := staticcall(
        gas,    // g = gas: whatever was passed already
        sload(_proxyRegistrySlot),  // a = address: address in storage
        _call,  // in = mem in  mem[in..(in+insize): set to free memory pointer
        0x24,   // insize = mem insize  mem[in..(in+insize): size of sig (bytes4) + bytes32 = 0x24
        _call,   // out = mem out  mem[out..(out+outsize): output assigned to this storage address
        0x20    // outsize = mem outsize  mem[out..(out+outsize): output should be 32byte slot (address size = 0x14 <  slot size 0x20)
      )

      // revert if not successful
      if iszero(success) {
        revert(0, 0)
      }

      _contractAddress := mload(_call) // assign result to return value
      mstore(0x40, add(_call, 0x24)) // advance free memory pointer by largest _call size
    }
  }

  // ensures that address has code/is contract
  function proxyIsContract(address _address)
    private
    view
    returns (bool)
  {
    uint256 _size;
    assembly { _size := extcodesize(_address) }
    return _size > 0;
  }

  //
  // proxy state setters
  //

  function proxyChangeMaster(address _newMaster)
    public
    returns (bool)
  {
    require(msg.sender == getContractAddress("PoaManager"));
    require(_newMaster != address(0));
    require(proxyMasterContract() != _newMaster);
    require(proxyIsContract(_newMaster));
    address _oldMaster = proxyMasterContract();
    bytes32 _proxyMasterContractSlot = proxyMasterContractSlot;
    assembly {
      sstore(_proxyMasterContractSlot, _newMaster)
    }

    emit ProxyUpgradedEvent(_oldMaster, _newMaster);
    getContractAddress("Logger").call(
      bytes4(keccak256("logProxyUpgradedEvent(address,address)")),
      _oldMaster, _newMaster
    );

    return true;
  }

  //
  // fallback for all proxied functions
  //

  function()
    external
    payable
  {
    bytes32 _proxyMasterContractSlot = proxyMasterContractSlot;
    assembly {
      // load address from first storage pointer
      let _master := sload(_proxyMasterContractSlot)

      // calldatacopy(t, f, s)
      calldatacopy(
        0x0, // t = mem position to
        0x0, // f = mem position from
        calldatasize // s = size bytes
      )

      // delegatecall(g, a, in, insize, out, outsize) => 0 on error 1 on success
      let success := delegatecall(
        gas, // g = gas
        _master, // a = address
        0x0, // in = mem in  mem[in..(in+insize)
        calldatasize, // insize = mem insize  mem[in..(in+insize)
        0x0, // out = mem out  mem[out..(out+outsize)
        0 // outsize = mem outsize  mem[out..(out+outsize)
      )

      // returndatacopy(t, f, s)
      returndatacopy(
        0x0, // t = mem position to
        0x0,  // f = mem position from
        returndatasize // s = size bytes
      )

      // check if call was a success and return if no errors & revert if errors
      if iszero(success) {
        revert(0, 0)
      }
        return(
          0x0,
          returndatasize
        )
    }
  }
}
