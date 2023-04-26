pragma solidity ^0.5.10;

interface P2WSHInterface {
  function getP2WSH(bytes32 loan, bool sez) external view returns (bytes memory, bytes32);
}
