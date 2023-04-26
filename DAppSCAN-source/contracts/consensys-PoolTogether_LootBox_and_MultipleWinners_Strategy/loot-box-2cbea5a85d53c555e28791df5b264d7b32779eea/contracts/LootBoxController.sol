// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Create2.sol";

import "./external/pooltogether/MinimalProxyLibrary.sol";
import "./LootBox.sol";

/// @title Allows users to plunder an address associated with an ERC721
/// @author Brendan Asselstine
/// @notice Counterfactually instantiates a "Loot Box" at an address unique to an ERC721 token.  The address for an ERC721 token can be computed and later
/// plundered by transferring token balances to the ERC721 owner.
contract LootBoxController {

  LootBox internal lootBoxActionInstance;
  bytes internal lootBoxActionBytecode;

  /// @notice Emitted when a Loot Box is plundered
  event Plundered(address indexed erc721, uint256 indexed tokenId, address indexed operator);

  /// @notice Emitted when a Loot Box is executed
  event Executed(address indexed erc721, uint256 indexed tokenId, address indexed operator);

  /// @notice Constructs a new controller.
  /// @dev Creates a new LootBox instance and an associated minimal proxy.
  constructor () public {
    lootBoxActionInstance = new LootBox();
    lootBoxActionBytecode = MinimalProxyLibrary.minimalProxy(address(lootBoxActionInstance));
  }

  /// @notice Computes the Loot Box address for a given ERC721 token.
  /// @dev The contract will not exist yet, so the Loot Box address will have no code.
  /// @param erc721 The address of the ERC721
  /// @param tokenId The ERC721 token id
  /// @return The address of the Loot Box.
  function computeAddress(address erc721, uint256 tokenId) external view returns (address) {
    return Create2.computeAddress(_salt(erc721, tokenId), keccak256(lootBoxActionBytecode));
  }

  /// @notice Allows anyone to transfer all given tokens in a Loot Box to the associated ERC721 owner.
  /// @dev A Loot Box contract will be counterfactually created, tokens transferred to the ERC721 owner, then destroyed.
  /// @param erc721 The address of the ERC721
  /// @param tokenId The ERC721 token id
  /// @param erc20s An array of ERC20 tokens whose entire balance should be transferred
  /// @param erc721s An array of structs defining ERC721 tokens that should be transferred
  /// @param erc1155s An array of struct defining ERC1155 tokens that should be transferred
  function plunder(
    address erc721,
    uint256 tokenId,
    IERC20[] calldata erc20s,
    LootBox.WithdrawERC721[] calldata erc721s,
    LootBox.WithdrawERC1155[] calldata erc1155s
  ) external {
    address payable owner = payable(IERC721(erc721).ownerOf(tokenId));
    LootBox lootBoxAction = _createLootBox(erc721, tokenId);
    lootBoxAction.plunder(erc20s, erc721s, erc1155s, owner);
    lootBoxAction.destroy(owner);

    emit Plundered(erc721, tokenId, msg.sender);
  }

  /// @notice Allows the owner of an ERC721 to execute abitrary calls on behalf of the associated Loot Box.
  /// @dev The Loot Box will be counterfactually created, calls executed, then the contract destroyed.
  /// @param erc721 The ERC721 address
  /// @param tokenId The ERC721 token id
  /// @param calls The array of call structs that define that target, amount of ether, and data.
  /// @return The array of call return values.
  function executeCalls(
    address erc721,
    uint256 tokenId,
    LootBox.Call[] calldata calls
  ) external returns (bytes[] memory) {
    address payable owner = payable(IERC721(erc721).ownerOf(tokenId));
    require(msg.sender == owner, "LootBoxController/only-owner");
    LootBox lootBoxAction = _createLootBox(erc721, tokenId);
    bytes[] memory result = lootBoxAction.executeCalls(calls);
    lootBoxAction.destroy(owner);

    emit Executed(erc721, tokenId, msg.sender);

    return result;
  }

  /// @notice Creates a Loot Box for the given ERC721 token.
  /// @param erc721 The ERC721 address
  /// @param tokenId The ERC721 token id
  /// @return The address of the newly created LootBox.
  function _createLootBox(address erc721, uint256 tokenId) internal returns (LootBox) {
    return LootBox(payable(Create2.deploy(0, _salt(erc721, tokenId), lootBoxActionBytecode)));
  }

  /// @notice Computes the CREATE2 salt for the given ERC721 token.
  /// @param erc721 The ERC721 address
  /// @param tokenId The ERC721 token id
  /// @return A bytes32 value that is unique to that ERC721 token.
  function _salt(address erc721, uint256 tokenId) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(erc721, tokenId));
  }
}
