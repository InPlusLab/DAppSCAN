pragma solidity >=0.4.21 <0.6.0;

contract IPDispatcher{
  function getTarget(bytes32 _key) public view returns (address);
}
