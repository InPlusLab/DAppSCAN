pragma solidity 0.5.13;

import "@openzeppelin/contracts/token/ERC721/ERC721Full.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "hardhat/console.sol";
import '../interfaces/IRCProxyXdai.sol';
import '../interfaces/IRCMarket.sol';

/// @title Reality Cards NFT Hub- xDai side
/// @author Andrew Stanger
contract RCNftHubXdai is Ownable, ERC721Full 
{
    ////////////////////////////////////
    //////// VARIABLES /////////////////
    ////////////////////////////////////

    /// @dev so only markets can move NFTs
    mapping (address => bool) public isMarket;
    /// @dev the market each NFT belongs to, so that it can only be moved in withdraw state
    mapping(uint256 => address) public marketTracker;

    /// @dev governance variables
    address public factoryAddress;

    ////////////////////////////////////
    /////////// CONSTRUCTOR ////////////
    ////////////////////////////////////

    constructor(address _factoryAddress) ERC721Full("RealityCards", "RC") public {
        setFactoryAddress(_factoryAddress);
    } 

    ////////////////////////////////////
    //////////// ADD MARKETS ///////////
    ////////////////////////////////////

    /// @dev so only markets can change ownership
    function addMarket(address _newMarket) external returns(bool) {
        require(msg.sender == factoryAddress, "Not factory");
        isMarket[_newMarket] = true;
        return true;
    }

    ////////////////////////////////////
    ////////// GOVERNANCE //////////////
    ////////////////////////////////////
    
    /// @dev address of RC factory contract, so only factory can mint
    function setFactoryAddress(address _newAddress) onlyOwner public {
        factoryAddress = _newAddress;
    }

    ////////////////////////////////////
    ///////// CORE FUNCTIONS ///////////
    ////////////////////////////////////

    // FACTORY ONLY
    function mintNft(address _originalOwner, uint256 _tokenId, string calldata _tokenURI) external returns(bool) {
        require(msg.sender == factoryAddress, "Not factory");
        _mint(_originalOwner, _tokenId); 
        _setTokenURI(_tokenId, _tokenURI);
        marketTracker[_tokenId] = _originalOwner;
        return true;
    }

    // MARKET ONLY
    function transferNft(address _currentOwner, address _newOwner, uint256 _tokenId) external returns(bool) {
        require(isMarket[msg.sender], "Not market");
        _transferFrom(_currentOwner, _newOwner, _tokenId);
        return true;
    }

    ////////////////////////////////////
    //////////// OVERRIDES /////////////
    ////////////////////////////////////
    /// @dev ensures NFTs can only be moved when market is resolved

    function transferFrom(address from, address to, uint256 tokenId) public {
        IRCMarket market = IRCMarket(marketTracker[tokenId]);
        require(market.state() == 3, "Incorrect state");
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        _transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public {
        IRCMarket market = IRCMarket(marketTracker[tokenId]);
        require(market.state() == 3, "Incorrect state");
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        _transferFrom(from, to, tokenId);
        _data;
    }

}
