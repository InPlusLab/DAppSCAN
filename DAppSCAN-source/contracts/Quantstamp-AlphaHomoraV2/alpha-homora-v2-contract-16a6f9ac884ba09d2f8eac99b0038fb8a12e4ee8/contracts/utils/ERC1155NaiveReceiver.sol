pragma solidity 0.6.12;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC1155/ERC1155Receiver.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC1155/IERC1155Receiver.sol';

contract ERC1155NaiveReceiver is ERC1155Receiver {
  function onERC1155Received(
    address operator,
    address from,
    uint id,
    uint value,
    bytes calldata data
  ) external override returns (bytes4) {
    return this.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address operator,
    address from,
    uint[] calldata ids,
    uint[] calldata values,
    bytes calldata data
  ) external override returns (bytes4) {
    return this.onERC1155BatchReceived.selector;
  }
}
