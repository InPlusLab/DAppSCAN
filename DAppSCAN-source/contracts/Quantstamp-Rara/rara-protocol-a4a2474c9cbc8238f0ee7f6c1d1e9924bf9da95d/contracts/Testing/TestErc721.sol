//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

/// @title TestErc1155
/// @dev This contract implements the ERC721 standard and is used for unit testing purposes only
/// Anyone can mint or burn tokens
contract TestErc721 is ERC721Upgradeable {
    /// @dev initializer to call after deployment, can only be called once
    function initialize(string memory name_, string memory symbol_)
        public
        initializer
    {
        __ERC721_init(name_, symbol_);
    }

    function mint(address to, uint256 tokenId) public {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) public {
        _burn(tokenId);
    }
}
