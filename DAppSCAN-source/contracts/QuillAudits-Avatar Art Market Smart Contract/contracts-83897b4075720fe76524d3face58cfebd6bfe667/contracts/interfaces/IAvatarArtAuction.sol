// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAvatarArtAuction{
    /**
     * @dev Owner create new auction for specific `tokenId`
     * 
     * REQUIREMENTS
     *  1. TokenId is not in other active auction
     *  2. Start time and end time is valid
     * 
     * @return Auction index
     */ 
    function createAuction(uint256 tokenId, uint256 startTime, uint256 endTime, uint256 price) external returns(uint256);
    
    /**
     * @dev Owner distributes NFT to winner
     * 
     *  REQUIREMENTS
     *  1. Auction ends
     */ 
    function distribute(uint256 auctionIndex) external returns(bool);
    
    /**
     * @dev User places a BID price to join specific auction 
     * 
     *  REQUIREMENTS
     *  1. Auction is active
     *  2. BID should be greater than current price
     */ 
    function place(uint256 auctionIndex, uint256 price) external returns(bool);
    
    /**
     * @dev Owner updates active status
     * 
     */ 
    function deactivateAuction(uint256 auctionIndex) external returns(bool);
    
     /**
     * @dev Owner update token price for specific auction, definied by `auctionIndex`
     * 
     * REQUIREMENTS
     *  1. Auction is not active, has not been started yet
     */ 
    function updateActionPrice(uint256 auctionIndex, uint256 price) external returns(bool);
    
    /**
     * @dev Owner updates auction time, definied by `auctionIndex`
     * 
     * REQUIREMENTS
     *  1. Auction is not active, has not been started yet
     */ 
    function updateActionTime(uint256 auctionIndex, uint256 startTime, uint256 endTime) external returns(bool);
}