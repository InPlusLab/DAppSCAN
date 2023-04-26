// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAvatarArtMarketplace.sol";
import "./AvatarArtBase.sol";

/**
* @dev Contract is used so that user can buy and sell NFT
* Business steps:
*   1. Artists submit selling information to system
*   2. Admin approve these informations and create an order.
*   3. If artist has any change, they can cancel this order
*   4. Other user can buy NFT by pay BNU token
*   Note that: The submiting and approving will be processed outside blockchain
*/
contract AvatarArtMarketplace is AvatarArtBase, IAvatarArtMarketplace{
    struct MarketHistory{
        address buyer;
        address seller;
        uint256 price;
        uint256 time;
    }
    
    uint256[] internal _tokens;
    
    //Mapping between tokenId and token price
    mapping(uint256 => uint256) internal _tokenPrices;
    
    //Mapping between tokenId and owner of tokenId
    mapping(uint256 => address) internal _tokenOwners;
    
    mapping(uint256 => MarketHistory[]) internal _marketHistories;
    
    constructor(address bnuTokenAddress, address avatarArtNFTAddress) 
        AvatarArtBase(bnuTokenAddress, avatarArtNFTAddress){}
    
    /**
     * @dev Create a selling order to sell NFT
     */
    function createSellOrder(uint256 tokenId, uint256 price) external onlyOwner override returns(bool){
        //Validate
        require(_tokenOwners[tokenId] == address(0), "Can not create sell order for this token");
        IERC721 avatarArtNFT = getAvatarArtNFT();
        
        address tokenOwner = avatarArtNFT.ownerOf(tokenId);
        
        //Transfer AvatarArtNFT to contract
        avatarArtNFT.safeTransferFrom(tokenOwner, address(this), tokenId);
        
        _tokenOwners[tokenId] = tokenOwner;
        _tokenPrices[tokenId] = price;
        _tokens.push(tokenId);
        
        emit NewSellOrderCreated(_msgSender(), _now(), tokenId, price);
        
        return true;
    }
    
    /**
     * @dev User that created sell order can cancel that order
     */ 
    function cancelSellOrder(uint256 tokenId) external override returns(bool){
        require(_tokenOwners[tokenId] == _msgSender(), "Forbidden to cancel sell order");

        IERC721 avatarArtNft = getAvatarArtNFT();
        //Transfer AvatarArtNFT from contract to sender
        avatarArtNft.safeTransferFrom(address(this), _msgSender(), tokenId);
        
        _tokenOwners[tokenId] = address(0);
        _tokenPrices[tokenId] = 0;
        _tokens = _removeFromTokens(tokenId);
        
        return true;
    }
    
    /**
     * @dev Get all active tokens that can be purchased 
     */ 
    function getTokens() external view returns(uint256[] memory){
        return _tokens;
    }
    
    /**
     * @dev Get token info about price and owner
     */ 
    function getTokenInfo(uint tokenId) external view returns(address, uint){
        return (_tokenOwners[tokenId], _tokenPrices[tokenId]);
    }
    
    
    function getMarketHistories(uint256 tokenId) external view returns(MarketHistory[] memory){
        return _marketHistories[tokenId];
    }
    
    /**
     * @dev Get token price
     */ 
    function getTokenPrice(uint256 tokenId) external view returns(uint){
        return _tokenPrices[tokenId];
    }
    
    /**
     * @dev Get token's owner
     */ 
    function getTokenOwner(uint256 tokenId) external view returns(address){
        return _tokenOwners[tokenId];
    }
    
    /**
     * @dev User purchases a BNU category
     */ 
    function purchase(uint tokenId) external override returns(uint){
        address tokenOwner = _tokenOwners[tokenId];
        require(tokenOwner != address(0),"Token has not been added");
        
        uint256 tokenPrice = _tokenPrices[tokenId];
        
        if(tokenPrice > 0){
            IERC20 bnuTokenContract = getBnuToken();    
            require(bnuTokenContract.transferFrom(_msgSender(), address(this), tokenPrice));
            uint256 feeAmount = 0;
            uint256 feePercent = getFeePercent();
            if(feePercent > 0){
                feeAmount = tokenPrice * feePercent / 100 / MULTIPLIER;
                require(bnuTokenContract.transfer(_owner, feeAmount));
            }
            require(bnuTokenContract.transfer(tokenOwner, tokenPrice - feeAmount));
        }
        
        //Transfer AvatarArtNFT from contract to sender
        getAvatarArtNFT().transferFrom(address(this),_msgSender(), tokenId);
        
        _marketHistories[tokenId].push(MarketHistory({
            buyer: _msgSender(),
            seller: _tokenOwners[tokenId],
            price: tokenPrice,
            time: block.timestamp
        }));
        
        _tokenOwners[tokenId] = address(0);
        _tokenPrices[tokenId] = 0;
        _tokens = _removeFromTokens(tokenId);
        
        emit Purchased(_msgSender(), tokenId, tokenPrice);
        
        return tokenPrice;
    }

    /**
     * @dev Owner withdraws ERC20 token from contract by `tokenAddress`
     */
    function withdrawToken(address tokenAddress) public onlyOwner{
        IERC20 token = IERC20(tokenAddress);
        token.transfer(_owner, token.balanceOf(address(this)));
    }
    
    /**
     * @dev Remove token item by value from _tokens and returns new list _tokens
    */ 
    function _removeFromTokens(uint tokenId) internal view returns(uint256[] memory){
        uint256 tokenCount = _tokens.length;
        uint256[] memory result = new uint256[](tokenCount-1);
        uint256 resultIndex = 0;
        for(uint tokenIndex = 0; tokenIndex < tokenCount; tokenIndex++){
            uint tokenItemId = _tokens[tokenIndex];
            if(tokenItemId != tokenId){
                result[resultIndex] = tokenItemId;
                resultIndex++;
            }
        }
        
        return result;
    }
    
    event NewSellOrderCreated(address indexed seller, uint256 time, uint256 tokenId, uint256 price);
    event Purchased(address indexed buyer, uint256 tokenId, uint256 price);
}