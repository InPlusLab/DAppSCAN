// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/token/ERC721/ERC721.sol";
import "oz-contracts/access/Ownable.sol";

import "../interfaces/IRegistry.sol";

struct PlayerInfo {
  bool playable;
  uint48 lastChallenge;
}

contract PLAYER is ERC721, Ownable, ISP721 {
  IRegistry registry;

  mapping(uint256 => PlayerInfo) public idToPlayerInfo;

  modifier authorized() {
    require(registry.authorized(msg.sender), "Caller is not authorized");
    _;
  }

  constructor(IRegistry registryAddress) ERC721("PLAYER", "SP20") {
    registry = IRegistry(registryAddress);
  }

  function safeMint(address to, uint256 tokenId) external override authorized {
    _safeMint(to, tokenId);
  }

  function updateLastChallenge(uint256 id) external authorized {
    idToPlayerInfo[id].lastChallenge = uint48(block.timestamp);
  }

  function _beforeTokenTransfer(
    address from, 
    address to, 
    uint256 tokenId
  ) internal override {
    registry.management().transferPlayerFrom(from, to, tokenId);  
  }
}