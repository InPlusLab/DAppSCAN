// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract Enum {
  enum Operation {
    Call,
    DelegateCall
  }
}

interface GnosisSafe {
  function getOwners() external view returns (address[] memory);

  function execTransaction(
    address to,
    uint256 value,
    bytes calldata data,
    uint8 operation,
    uint256 safeTxGas,
    uint256 dataGas,
    uint256 gasPrice,
    address gasToken,
    address refundReceiver,
    bytes calldata signatures
  ) external payable;
}

interface IGuard {
  function checkTransaction(
    address to,
    uint256 value,
    bytes memory data,
    Enum.Operation operation,
    uint256 safeTxGas,
    uint256 baseGas,
    uint256 gasPrice,
    address gasToken,
    address payable refundReceiver,
    bytes memory signatures,
    address msgSender
  ) external;

  function checkAfterExecution(bytes32, bool) external view;
}
