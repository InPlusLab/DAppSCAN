// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./core/Ownable.sol";

contract AvatarArtBase is Ownable, IERC721Receiver{
    uint256 public MULTIPLIER = 1000;
    
    IERC20 private _bnuToken;
    IERC721 private _avatarArtNFT;
    
    uint256 private _feePercent;       //Multipled by 1000
    
    constructor(address bnuTokenAddress, address avatarArtNFTAddress){
        _bnuToken = IERC20(bnuTokenAddress);
        _avatarArtNFT = IERC721(avatarArtNFTAddress);
        _feePercent = 100;        //0.1%
    }
    
    /**
     * @dev Get BNU token 
     */
    function getBnuToken() public view returns(IERC20){
        return _bnuToken;
    }
    
    /**
     * @dev Get AvatarArt NFT
     */
    function getAvatarArtNFT() public view returns(IERC721){
        return _avatarArtNFT;
    }
    
    /**
     * @dev Get fee percent, this fee is for seller
     */ 
    function getFeePercent() public view returns(uint){
        return _feePercent;
    }
    
    /**
     * @dev Set AvatarArtNFT contract 
     */
    function setAvatarArtNFT(address newAddress) public onlyOwner{
        require(newAddress != address(0), "Zero address");
        _avatarArtNFT = IERC721(newAddress);
    }
    
    /**
     * @dev Set BNU token 
     */
    function setBnuToken(address newAddress) public onlyOwner{
        require(newAddress != address(0), "Zero address");
        _bnuToken = IERC20(newAddress);
    }
    
    /**
     * @dev Set fee percent
     */
    function setFeePercent(uint feePercent) public onlyOwner{
        _feePercent = feePercent;
    }
    
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external view override returns (bytes4){
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}