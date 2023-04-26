pragma solidity 0.5.13;

import "@openzeppelin/contracts/token/ERC721/ERC721Full.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "hardhat/console.sol";

/// @title Reality Cards NFT Hub- mainnet side
/// @author Andrew Stanger
contract RCNftHubMainnet is Ownable, ERC721Full 
{
    ////////////////////////////////////
    //////// VARIABLES /////////////////
    ////////////////////////////////////

    address public mainnetProxyAddress;

    ////////////////////////////////////
    //////// CONSTRUCTOR ///////////////
    ////////////////////////////////////

    constructor() ERC721Full("RealityCards", "RC") public {}

    ////////////////////////////////////
    ////////// GOVERNANCE //////////////
    ////////////////////////////////////
    
    /// @dev address of Mainnet Proxy contract, so only this contract can mint nfts
    function setProxyMainnetAddress(address _newAddress) onlyOwner public {
        mainnetProxyAddress = _newAddress;
    }

    ////////////////////////////////////
    ///////// CORE FUNCTIONS ///////////
    ////////////////////////////////////

    function mintNft(uint256 _tokenId, string calldata _tokenURI, address _originalOwner) external {
        require(msg.sender == mainnetProxyAddress, "Not proxy");
        _mint(_originalOwner, _tokenId); 
        _setTokenURI(_tokenId, _tokenURI);
    }

}
