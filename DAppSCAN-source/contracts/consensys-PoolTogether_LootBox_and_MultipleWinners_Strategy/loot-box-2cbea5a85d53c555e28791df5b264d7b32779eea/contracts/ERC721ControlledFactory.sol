// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/utils/Create2.sol";

import "./external/pooltogether/MinimalProxyLibrary.sol";
import "./ERC721Controlled.sol";

/// @title Factory to create ERC721Controlled tokens
/// @author Brendan Asselstine <brendan@pooltogether.com>
/// @notice Creates new ERC721Controlled tokens using the minimal proxy pattern.
contract ERC721ControlledFactory {
  using SafeMath for uint256;

  /// @notice The instance of the ERC721Controlled that the minimal proxies will point to
  ERC721Controlled public erc721ControlledInstance;
  bytes internal erc721ControlledBytecode;

  /// @notice The nonces that ensure a sender will always produce a unique address
  mapping(address => uint256) public nonces;

  /// @notice Initializes a new factory.
  /// @dev Will create an ERC721Controlled instance and the minimal proxy bytecode that points to it.
  constructor () public {
    erc721ControlledInstance = new ERC721Controlled();
    erc721ControlledBytecode = MinimalProxyLibrary.minimalProxy(address(erc721ControlledInstance));
  }

  /// @notice Computes the address that the next ERC721Controlled will be deployed to
  /// @param creator The address that will call create
  /// @return The address of the ERC721Controlled
  function computeAddress(address creator) external view returns (address) {
    return Create2.computeAddress(_salt(creator), keccak256(erc721ControlledBytecode));
  }

  /// @notice Creates an ERC721Controlled contract
  /// @return The address of the newly created LootBox.
  function createERC721Controlled(
    string memory name,
    string memory symbol,
    string memory baseURI
  ) external returns (ERC721Controlled) {
    ERC721Controlled result = ERC721Controlled(payable(Create2.deploy(0, _salt(msg.sender), erc721ControlledBytecode)));
    nonces[msg.sender] = nonces[msg.sender].add(1);
    result.initialize(name, symbol, baseURI, msg.sender);
    return result;
  }

  /// @notice Computes the CREATE2 salt for the given address
  /// @param creator The user creating the token
  /// @return A bytes32 value that is unique to that ERC721 token.
  function _salt(address creator) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(creator, nonces[creator]));
  }
}
