// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
 
contract HeroAssets is ERC721, ERC721Enumerable, Pausable, AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    string baseURI = "https://meta.heroesempires.com/heroes/"; //"https://meta.heroesempires.com/heroes/";
    struct HeroesInfo {
        uint256 heroesNumber;
        string name;
        string race;
        string class;
        string tier; 
        string tierBasic;
    }
    mapping(uint256 => HeroesInfo) public heroesNumber; // tokenId => Heroes
    function getHeroesNumber(uint256 _tokenId) public view returns(HeroesInfo memory) {
        return heroesNumber[_tokenId];
    }

    constructor() ERC721("Hero Assets", "HEA") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
    }
    
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }
    function setBaseURI(string memory _baseUri) public onlyRole(DEFAULT_ADMIN_ROLE){
        baseURI = _baseUri;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function safeMint(address to, uint256 tokenId) public onlyRole(MINTER_ROLE) {
        _safeMint(to, tokenId);
    }
    function burn(address owner, uint256 tokenId) public onlyRole(MINTER_ROLE) {
        require(ownerOf(tokenId) == owner, "ERC721: burn of token that is not own" );
        _burn(tokenId);
    }
    function editTier(uint256 tokenId, string memory _tier) public onlyRole(MINTER_ROLE) {
        heroesNumber[tokenId].tier = _tier;
    }
    function addHeroesNumber(uint256 tokenId, uint256 _heroesNumber, string memory name, string memory race, string memory class, string memory tier, string memory tierBasic) public onlyRole(MINTER_ROLE) {
        heroesNumber[tokenId] = HeroesInfo( _heroesNumber, name, race, class, tier, tierBasic);
    }
    function deleteHeroesNumber(uint256 tokenId) public onlyRole(MINTER_ROLE) {
        delete heroesNumber[tokenId];
    }
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }
    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}