// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./core/Ownable.sol";
import "./interfaces/IAvatarArtArtistKYC.sol";

contract AvatarArtNFT is ERC721, Ownable{
    IAvatarArtArtistKYC internal _avatarArtArtistKYC;
    
    constructor() ERC721("AvatarArt", "AvatarArtNFT"){}
    
    /**
     * @dev Create new NFT 
     */
    function create(uint tokenId) external returns(bool){
        require(_avatarArtArtistKYC.isVerified(_msgSender()), "Forbidden");
        _safeMint(_msgSender(), tokenId);
        return true;
    }
    
    /**
     * @dev Burn a NFT
     */ 
    function burn(uint tokenId) external onlyOwner returns(bool){
        _burn(tokenId);
        return true;
    }
    
    function getAvatarArtArtistKYC() external view returns(IAvatarArtArtistKYC){
        return _avatarArtArtistKYC;
    }
    
    function setAvatarArtArtistKYC(address newAddress) external onlyOwner{
        require(newAddress != address(0), "Zero address");
        _avatarArtArtistKYC = IAvatarArtArtistKYC(newAddress);
    }
    
    /**
     * @dev Base NFT Metadata URI
     */ 
    function _baseURI() internal view override virtual returns (string memory) {
        return "https://cdn.avatarart.org/nft/collections/";
    }
}