// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Mintable is ERC721 {

  event ERC721Initialized(
    string name,
    string symbol,
    string baseURI
  );

  constructor (
    string memory name,
    string memory symbol,
    string memory baseURI_
  ) public ERC721(name, symbol) {
    _setBaseURI(baseURI_);

    emit ERC721Initialized(name, symbol, baseURI_);
  }

  function mint(address user, uint256 id) external returns (address) {
    _mint(user, id);
  }

}
