pragma solidity ^0.5.16;
import "../interfaces/ISWSupplyManager.sol";


contract FactoryMock {

  ISWSupplyManager internal factoryManager; //SkyWeaver Curencies Factory Manager Contract

  constructor(address _factoryManagerAddr) public {
    factoryManager = ISWSupplyManager(_factoryManagerAddr);
  }

  function batchMint(
    address _to,
    uint256[] memory _ids,
    uint256[] memory _amounts,
    bytes memory _data) public
  {
    factoryManager.batchMint(_to, _ids, _amounts, _data);
  }

  function mint(
    address _to,
    uint256 _id,
    uint256 _amount,
    bytes memory _data) public
  {
    factoryManager.mint(_to, _id, _amount, _data);
  }

}