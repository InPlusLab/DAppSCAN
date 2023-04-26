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

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Horse is Ownable, ERC721URIStorage {
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using Strings for uint256;

    event Mint(address receiver, uint256 tokenId);
    event ChangeBaseURI(address admin, string uri);
    event UpdateAge(address user,uint256 tokenId,uint256 age);

    Counters.Counter private _tokenIds;
    string public baseURI;
    mapping(uint256 => string) private uri;
    mapping(uint256 => uint256) private rarity;
    mapping(uint256 => uint256) private age;
    mapping(uint256 => uint256) private bornAt;
    mapping(address => bool) public minter;
    uint256 public retriedAge;

    modifier onlyMinter() {
        require(minter[msg.sender], "only minter.");
        _;
    }

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {}

    function setMinter(address _minter, bool _isMinter) external {
        minter[_minter] = _isMinter;
    }

    // Mint all NFT on deploy and keep data for treading
    function mint(
        address _receiver,
        string memory _uri,
        uint256 _tokenId,
        uint256 _rarity,
        uint256 _age
    ) public onlyMinter {
        _mint(_receiver, _tokenId);
        uri[_tokenId] = _uri;
        rarity[_tokenId] = _rarity;
        bornAt[_tokenId] = block.number;
        age[_tokenId] = _age;

        emit Mint(_receiver, _tokenId);
    }

    function mints(
        address[] memory _receiver,
        string[] memory _uri,
        uint256[] memory _tokenId,
        uint256[] memory _rarity,
        uint256[] memory _age
    ) external onlyMinter {
        for (uint256 index = 0; index < _receiver.length; index++) {
            mint(
                _receiver[index],
                _uri[index],
                _tokenId[index],
                _rarity[index],
                _age[index]
            );
        }
    }

    function getPopularity(uint256 _tokenId) public view returns (uint256) {
        if (block.number - bornAt[_tokenId] > age[_tokenId]) {
            return rarity[_tokenId].div(5);
        } else {
            return rarity[_tokenId];
        }
    }

    function setAge(uint256 _tokenId, uint256 _age) external onlyOwner {
        age[_tokenId] = _age;

        emit UpdateAge(msg.sender, _tokenId, _age);
    }

    function getRemainAge(uint256 _tokenId) external view returns (uint256) {
        if (age[_tokenId] > block.number.sub(bornAt[_tokenId])) {
            return age[_tokenId].sub(block.number.sub(bornAt[_tokenId]));
        } else {
            return 0;
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

        emit ChangeBaseURI(msg.sender, _uri);
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
