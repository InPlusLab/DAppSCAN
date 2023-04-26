//SPDX-License-Identifier: Unlicense
/*
░██████╗██████╗░███████╗███████╗██████╗░░░░░░░░██████╗████████╗░█████╗░██████╗░
██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗░░░░░░██╔════╝╚══██╔══╝██╔══██╗██╔══██╗
╚█████╗░██████╔╝█████╗░░█████╗░░██║░░██║█████╗╚█████╗░░░░██║░░░███████║██████╔╝
░╚═══██╗██╔═══╝░██╔══╝░░██╔══╝░░██║░░██║╚════╝░╚═══██╗░░░██║░░░██╔══██║██╔══██╗
██████╔╝██║░░░░░███████╗███████╗██████╔╝░░░░░░██████╔╝░░░██║░░░██║░░██║██║░░██║
╚═════╝░╚═╝░░░░░╚══════╝╚══════╝╚═════╝░░░░░░░╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚═╝
*/
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Pack is Ownable, ERC721URIStorage {
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private _tokenIds;
    string public baseURI;

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {}

    // Mint all NFT on deploy and keep data for treading
    function mint(address _receiver) external onlyOwner {
        uint256 newItemId = _tokenIds.current();
        _mint(_receiver, newItemId);
        _tokenIds.increment();
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(_tokenId), "URI query for nonexistent token");
        return string(abi.encodePacked(baseURI, _tokenId.toString(), ".json"));
    }

    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        _safeTransfer(from, to, tokenId, _data);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }
}
