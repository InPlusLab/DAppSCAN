// contracts/claim/SuperRareTokenMerkleDrop.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract SuperRareTokenMerkleDrop is ContextUpgradeable {
  address _owner;
  bytes32 public _merkleRoot;
  IERC20Upgradeable _superRareToken;
  mapping (address => bool) public _claimed;

  event TokensClaimed(
    address addr,
    uint256 amt
  );

  constructor(address superRareToken, bytes32 merkleRoot) {
    _owner = _msgSender();
    _superRareToken = IERC20Upgradeable(superRareToken);
    _merkleRoot = merkleRoot;
  }

  function claim(uint256 amount, bytes32[] memory proof) public {
    require(verifyEntitled(_msgSender(), amount, proof), "The proof could not be verified.");
    require(!_claimed[_msgSender()], "You have already withdrawn your entitled token.");

    _claimed[_msgSender()] = true;

    require(_superRareToken.transfer(_msgSender(), amount));
    emit TokensClaimed(_msgSender(), amount);
  }

  function verifyEntitled(address recipient, uint value, bytes32[] memory proof) public view returns (bool) {
        // We need to pack the 20 bytes address to the 32 bytes value
        // to match with the proof
        bytes32 leaf = keccak256(abi.encodePacked(recipient, value));
        return verifyProof(leaf, proof);
    }

  function verifyProof(bytes32 leaf, bytes32[] memory proof) internal view returns (bool) {
        bytes32 currentHash = leaf;

        for (uint i = 0; i < proof.length; i += 1) {
            currentHash = parentHash(currentHash, proof[i]);
        }

        return currentHash == _merkleRoot;
    }

  function parentHash(bytes32 a, bytes32 b) internal pure returns (bytes32) {
    return a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
  }
}
