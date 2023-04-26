// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "./common/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./common/meta-transactions/ContextMixin.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";


/**
 * @title COGI ERC721 Token
 * @author COGI Inc
*/

contract CogiERC721 is
    Initializable,
    ContextUpgradeable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC721BurnableUpgradeable,
    ERC721URIStorageUpgradeable,
    ContextMixin,
    EIP712Upgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address proxyRegistryAddress;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _tokenIds;
    mapping(string => uint8) cids;
    string private __baseURI;
    mapping(string => uint8) locks;
    
    mapping(address => uint256) private nonces;
    
    event onAwardItem(
        address recipient,
        string cid,
        uint256 tokenId
    );

    event onTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    );

    event onTokenBurn(
        uint256 tokenId
    );

    function initialize(string memory _name, string memory _symbol, address contract_address) public virtual initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init();
        __Context_init_unchained();
        __AccessControlEnumerable_init_unchained();
        __ERC721_init_unchained(_name, _symbol);
        __ERC721Burnable_init_unchained();
        proxyRegistryAddress = contract_address;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    function _verify(bytes32 digest, bytes memory signature)
    internal view returns (bool)
    {
        return hasRole(MINTER_ROLE, ECDSAUpgradeable.recover(digest, signature));
    }

    function awardItem(address recipient, string memory cid) public virtual
        returns (uint256)
    {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC721: must have minter role to mint");
        require(cids[cid] != 1);
        cids[cid] = 1;        
        uint256 newTokenId = _tokenIds.current();
        _tokenIds.increment();
        _mint(recipient, newTokenId);
        _setTokenURI(newTokenId, cid);
        setApprovalForAll(proxyRegistryAddress, true);
        emit onAwardItem(recipient, cid, newTokenId);
        return newTokenId;
    }

    function burn(uint256 tokenId) public virtual override{
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not owner nor approved");
        _burn(tokenId);
        emit onTokenBurn(tokenId);
    }

    function addMinter(address account) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ERC721: Must have admin role to addMinter");
        grantRole(MINTER_ROLE, account);
    }

    function removeMinter(address account) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ERC721: must have admin role to removeMinter");
        revokeRole(MINTER_ROLE, account);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerableUpgradeable, ERC721Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return __baseURI;
    }

    function _burn(uint256 tokenId) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
        super._burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721Upgradeable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

}
