// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./AvatarArtERC20.sol";
import ".././core/Ownable.sol";

/**
* @dev Contract is used to deploy an ERC20 token that stands for an NFT
* With high valuable NFT, it will be divided into small part, 
* therefore an ERC20 token is created so that users can buy some percents
* This ERC20 token will be traded in AvatarArtExchange
 */
contract AvatarArtTokenDeployer is Ownable, IERC721Receiver {
    struct TokenInfo{
        string name;
        string symbol;
        uint256 totalSupply;
        address tokenOwner;
        address tokenAddress;
        address pairToAddress;
        bool isApproved;
    }

    IERC721 public _avatarArtNft;

    //`Pair to address` is allowed to create pair with new token
    //Mapping Address => Boolean
    mapping(address => bool) public _allowedPairs;
    mapping(uint256 => TokenInfo) public _tokenInfos;

    constructor(address avatarNftAddress){
        _avatarArtNft = IERC721(avatarNftAddress);
    }

    function setAvatarArtNft(address avatarNftAddress) external onlyOwner {
        _avatarArtNft = IERC721(avatarNftAddress);
    }

    /**
    * @dev System administrator approve for NFT with `tokenId` can generate ERC20 token
    */
    function approve(
        uint256 tokenId,
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address tokenOwner,
        address pairToAddress) external onlyOwner{
        require(tokenOwner != address(0), "Token owner is address zero");
        require(_allowedPairs[pairToAddress], "pairToAddress is not allowed");

        _tokenInfos[tokenId] = TokenInfo({
            name: name,
            symbol: symbol,
            totalSupply: totalSupply,
            tokenOwner: tokenOwner,
            tokenAddress: address(0),
            pairToAddress: pairToAddress,
            isApproved: true
        });
    }

    /**
    * @dev Artist deploys ERC20 token
    */
    function deployContract(uint256 tokenId) public returns(address){
        TokenInfo storage tokenInfo = _tokenInfos[tokenId];
        require(tokenInfo.isApproved, "NFT has not been approved");

        _avatarArtNft.safeTransferFrom(tokenInfo.tokenOwner, address(this), tokenId);

        AvatarArtERC20 deployedContract = new AvatarArtERC20(tokenInfo.name, tokenInfo.symbol, tokenInfo.totalSupply, tokenInfo.tokenOwner, _owner);
        tokenInfo.tokenAddress = address(deployedContract);
        
        emit NftTokenDeployed(tokenId, tokenInfo.tokenAddress, tokenInfo.name, tokenInfo.symbol, tokenInfo.totalSupply, tokenInfo.pairToAddress, _msgSender());
        return tokenInfo.tokenAddress;
    }

    /**
    * @dev Burn all ERC20 token if sender has all token to get NFT
    */
    function burnToken(uint256 tokenId) external{
        TokenInfo storage tokenInfo = _tokenInfos[tokenId];
        require(tokenInfo.tokenAddress != address(0));

        IERC20 token = IERC20(tokenInfo.tokenAddress);
        require(token.balanceOf(_msgSender()) == token.totalSupply());

        token.transferFrom(_msgSender(), address(0), token.totalSupply());
        _avatarArtNft.safeTransferFrom(address(this), _msgSender(), tokenId);

        tokenInfo.name = "";
        tokenInfo.symbol = "";
        tokenInfo.totalSupply = 0;
        tokenInfo.tokenAddress = address(0);
        tokenInfo.tokenOwner = address(0);
        tokenInfo.isApproved = false;

        emit NftTokenBurned(_msgSender(), tokenId);
    }

    /**
    * @dev Allow generated ERC20 token to be trade with specific token
    */
    function toggleAllowedPair(address pairAddress) external onlyOwner{
        _allowedPairs[pairAddress] = !_allowedPairs[pairAddress];
    }

    /**
    * @dev Withdraw NFT from contract
    * For some reason, contract updating as example
    */
    function withdrawNft(uint256 tokenId, address receipent) external onlyOwner{
        _avatarArtNft.safeTransferFrom(address(this), receipent, tokenId);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external view override returns (bytes4){
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
    
    event NftTokenDeployed(uint256 tokenId, address tokenAddress, string name, string symbol, uint256 totalSupply, address pairToAddress, address balanceAddress);
    event NftTokenBurned(address owner, uint256 tokenId);
}