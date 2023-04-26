pragma solidity 0.4.23;

// limited ContractRegistry definition
interface IRegistry {
  function owner() 
    external 
    returns(address);

  function updateContractAddress(
    string _name,
    address _address
  )
    external
    returns (address);

  function getContractAddress(
    string _name
  )
    external
    view
    returns (address);
}