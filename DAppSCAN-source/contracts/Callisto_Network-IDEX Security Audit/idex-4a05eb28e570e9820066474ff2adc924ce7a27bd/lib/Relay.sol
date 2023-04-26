pragma solidity ^0.4.6;
contract Relay {
  function relayTransferFrom(address token, address from, address to, uint256 value) returns (bool success);
  function relayTransfer(address token, uint256 amount) returns (bool success);
  function relaySendEther(address target, uint256 amount) returns (bool success);
}
