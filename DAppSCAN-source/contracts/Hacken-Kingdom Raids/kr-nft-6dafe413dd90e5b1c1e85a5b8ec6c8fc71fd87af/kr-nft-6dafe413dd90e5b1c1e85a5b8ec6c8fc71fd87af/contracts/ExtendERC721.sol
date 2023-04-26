// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ExtendERC721 is ERC721Enumerable, AccessControlEnumerable, Ownable {

    constructor(string memory name_, string memory symbol_)ERC721(name_, symbol_)
    {}

    string private baseURIExtended;

    function setBaseURI(string memory baseURI) external onlyOwner {
        baseURIExtended = baseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURIExtended;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override(ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function burn(uint256 tokenId) public virtual {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721Burnable: caller is not owner nor approved");
        _burn(tokenId);
    }


}
