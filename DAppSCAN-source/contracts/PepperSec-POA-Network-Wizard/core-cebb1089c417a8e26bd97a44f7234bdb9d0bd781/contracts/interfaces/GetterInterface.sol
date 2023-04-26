pragma solidity ^0.4.23;

interface GetterInterface {
  function read(bytes32 exec_id, bytes32 location) external view returns (bytes32 data);
  function readMulti(bytes32 exec_id, bytes32[] locations) external view returns (bytes32[] data);
}
