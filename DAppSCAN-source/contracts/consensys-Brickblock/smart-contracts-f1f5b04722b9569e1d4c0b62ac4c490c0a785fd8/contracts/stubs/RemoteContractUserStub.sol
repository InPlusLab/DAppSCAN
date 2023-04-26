pragma solidity 0.4.23;

import "../interfaces/IRegistry.sol";

// shortened version of actual contract in order to save on costs
interface RemoteContractStubInterface {
  function testNumber()
    external
    view
    returns (uint256);

  function add(
    uint256 _num1, 
    uint256 _num2
  )
    external
    pure
    returns (uint256);

  function setTestNumber(
    uint256 _number
  )
    external
    returns (bool);
}


contract RemoteContractUserStub {

  IRegistry private registry;

  constructor(
    address _registryAddress
  )
    public
  {
    require(_registryAddress != address(0));
    registry = IRegistry(_registryAddress);
  }

  function getRemoteContractStub()
    private
    view
    returns (RemoteContractStubInterface)
  {
    return RemoteContractStubInterface(
      registry.getContractAddress("TestName")
    );
  }

  function remoteAdd(uint256 _num1, uint256 _num2)
    public
    view
    returns (uint256)
  {
    RemoteContractStubInterface genericRemoteContract = getRemoteContractStub();
    return genericRemoteContract.add(_num1, _num2);
  }

  function remoteTestNumber()
    public
    view
    returns (uint256)
  {
    RemoteContractStubInterface genericRemoteContract = getRemoteContractStub();
    return genericRemoteContract.testNumber();
  }

  function remoteSetNumber(uint256 _newNumber)
    public
    returns (bool)
  {
    RemoteContractStubInterface genericRemoteContract = getRemoteContractStub();
    require(genericRemoteContract.setTestNumber(_newNumber));
    return true;
  }
}
