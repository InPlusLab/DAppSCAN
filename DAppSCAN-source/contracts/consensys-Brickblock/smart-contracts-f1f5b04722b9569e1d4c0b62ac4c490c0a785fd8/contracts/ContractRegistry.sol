pragma solidity 0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";


contract ContractRegistry is Ownable {

  uint8 public constant version = 1;
  address public owner;
  mapping (bytes32 => address) private contractAddresses;

  event UpdateContractEvent(string name, address indexed contractAddress);

  function updateContractAddress(string _name, address _address)
    public
    onlyOwner
    returns (address)
  {
    contractAddresses[keccak256(_name)] = _address;
    emit UpdateContractEvent(_name, _address);
  }

  function getContractAddress(string _name)
    public
    view
    returns (address)
  {
    require(contractAddresses[keccak256(_name)] != address(0));
    return contractAddresses[keccak256(_name)];
  }

  function getContractAddress32(bytes32 _name32)
    public
    view
    returns (address)
  {
    require(contractAddresses[_name32] != address(0));
    return contractAddresses[_name32];
  }

  // prevent anyone from sending funds other than selfdestructs of course :)
  function()
    public
    payable
  {
    revert();
  }
}
