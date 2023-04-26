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

contract Facility is Ownable, ERC721URIStorage {
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using Strings for uint256;

    event Mint(address receiver, uint256 tokenId);
    event ChangeBaseURI (address admin,string uri);

    Counters.Counter private _tokenIds;
    string public baseURI;
    mapping(uint256 => string) private uri;
    mapping(uint256 => uint256) public multipliers;
    mapping(uint256 => uint256) public popularity;
    mapping(uint256 => uint256) public size;
    mapping(uint256 => bool) public isStable;

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {}

    // Mint all NFT on deploy and keep data for treading
    function mintStable(
        address _receiver,
        string memory _uri,
        uint256 _tokenId,
        uint256 _multiplier,
        uint256 _size
    ) public onlyOwner {
        _mint(_receiver, _tokenId);
        uri[_tokenId] = _uri;
        isStable[_tokenId] = true;
        multipliers[_tokenId] = _multiplier;
        size[_tokenId] = _size;
        emit Mint(_receiver, _tokenId);
    }

    function mintStables(
        address[] memory _receiver,
        string[] memory _uri,
        uint256[] memory _tokenId,
        uint256[] memory _multiplier,
        uint256[] memory _size
    ) external onlyOwner {
        for (uint256 index = 0; index < _receiver.length; index++) {
            mintStable(
                _receiver[index],
                _uri[index],
                _tokenId[index],
                _multiplier[index],
                _size[index]
            );
        }
    }

    function mintFacility(
        address _receiver,
        string memory _uri,
        uint256 _tokenId,
        uint256 _popularity,
        uint256 _size
    ) public onlyOwner {
        _mint(_receiver, _tokenId);
        uri[_tokenId] = _uri;
        popularity[_tokenId] = _popularity;
        size[_tokenId] = _size;

        emit Mint(_receiver, _tokenId);
    }

    function mintFacilitys(
        address[] memory _receiver,
        string[] memory _uri,
        uint256[] memory _tokenId,
        uint256[] memory _popularity,
        uint256[] memory _size
    ) external onlyOwner {
        for (uint256 index = 0; index < _receiver.length; index++) {
            mintFacility(
                _receiver[index],
                _uri[index],
                _tokenId[index],
                _popularity[index],
                _size[index]
            );
        }
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(_tokenId), "URI query for nonexistent token");
        return string(abi.encodePacked(baseURI, uri[_tokenId], ".json"));
    }

    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;

        emit ChangeBaseURI(msg.sender,_uri);
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
