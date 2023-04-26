pragma solidity ^0.5.4;

import "erc721o/contracts/ERC721OBackwardCompatible.sol";

import "./Lib/usingRegistry.sol";

/// @title Opium.TokenMinter contract implements ERC721O token standard for minting, burning and transferring position tokens
contract TokenMinter is ERC721OBackwardCompatible, usingRegistry {
    /// @notice Calls constructors of super-contracts
    /// @param _baseTokenURI string URI for token explorers
    /// @param _registry address Address of Opium.registry
    constructor(string memory _baseTokenURI, address _registry) public ERC721OBackwardCompatible(_baseTokenURI) usingRegistry(_registry) {}

    /// @notice Mints LONG and SHORT position tokens
    /// @param _buyer address Address of LONG position receiver
    /// @param _seller address Address of SHORT position receiver
    /// @param _derivativeHash bytes32 Hash of derivative (ticker) of position
    /// @param _quantity uint256 Quantity of positions to mint
    function mint(address _buyer, address _seller, bytes32 _derivativeHash, uint256 _quantity) external onlyCore {
        _mint(_buyer, _seller, _derivativeHash, _quantity);
    }

    /// @notice Mints only LONG position tokens for "pooled" derivatives
    /// @param _buyer address Address of LONG position receiver
    /// @param _derivativeHash bytes32 Hash of derivative (ticker) of position
    /// @param _quantity uint256 Quantity of positions to mint
    function mint(address _buyer, bytes32 _derivativeHash, uint256 _quantity) external onlyCore {
        _mintLong(_buyer, _derivativeHash, _quantity);
    }

    /// @notice Burns position tokens
    /// @param _tokenOwner address Address of tokens owner
    /// @param _tokenId uint256 tokenId of positions to burn
    /// @param _quantity uint256 Quantity of positions to burn
    function burn(address _tokenOwner, uint256 _tokenId, uint256 _quantity) external onlyCore {
        _burn(_tokenOwner, _tokenId, _quantity);
    }

    /// @notice ERC721 interface compatible function for position token name retrieving
    /// @return Returns name of token
    function name() external view returns (string memory) {
        return "Opium Network Position Token";
    }

    /// @notice ERC721 interface compatible function for position token symbol retrieving
    /// @return Returns symbol of token
    function symbol() external view returns (string memory) {
        return "ONP";
    }

    /// VIEW FUNCTIONS

    /// @notice Checks whether _spender is approved to spend tokens on _owners behalf or owner itself
    /// @param _spender address Address of spender
    /// @param _owner address Address of owner
    /// @param _tokenId address tokenId of interest
    /// @return Returns whether _spender is approved to spend tokens
    function isApprovedOrOwner(
        address _spender,
        address _owner,
        uint256 _tokenId
    ) public view returns (bool) {
        return (
        _spender == _owner ||
        getApproved(_tokenId, _owner) == _spender ||
        isApprovedForAll(_owner, _spender) ||
        isOpiumSpender(_spender)
        );
    }

    /// @notice Checks whether _spender is Opium.TokenSpender
    /// @return Returns whether _spender is Opium.TokenSpender
    function isOpiumSpender(address _spender) public view returns (bool) {
        return _spender == registry.getTokenSpender();
    }
}
