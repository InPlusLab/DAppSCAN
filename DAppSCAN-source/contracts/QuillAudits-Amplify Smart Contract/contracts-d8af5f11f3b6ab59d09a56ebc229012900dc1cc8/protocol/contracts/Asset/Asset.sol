// SPDX-License-Identifier: MIT
/// @dev size: 7.060 Kbytes
// SWC-103-Floating Pragma: L4
pragma solidity ^0.8.0;

import "./AssetStorage.sol";
import "./AssetInterface.sol";
import "./RiskModel.sol";

import "../utils/Counters.sol";
import "../security/Ownable.sol";

contract Asset is AssetInterface, AssetStorage, Ownable {
    using Counters for Counters.Counter;
    using Risk for Risk.Data;

    Counters.Counter private _tokenIds;
    Risk.Data private riskModel;

    event TokenizeAsset(uint256 indexed tokenId, string tokenHash,string tokenRating, uint256 value, string tokenURI, uint256 maturity, uint256 uploadedAt);

    constructor() ERC721("AmplifyAsset", "AAT") {}

    function tokenizeAsset(
        string memory tokenHash, 
        string memory tokenRating, 
        uint256 value, 
        uint256 maturity, 
        string memory tokenURI
    ) external returns (uint256) {
        _tokenIds.increment();

        uint256 newAssetId = _tokenIds.current();
        _mint(msg.sender, newAssetId);
        
        _tokens[newAssetId] = Token(
            value,
            maturity,
            riskModel.getInterestRate(tokenRating),
            riskModel.getAdvanceRate(tokenRating),
            tokenRating,
            tokenHash,
            false
        );
        _setTokenURI(newAssetId, tokenURI);

        emit TokenizeAsset(newAssetId, tokenHash, tokenRating, value, tokenURI, maturity, block.timestamp);
        return newAssetId;
    }

    function totalSupply() external view returns (uint256) {
        return _tokenIds.current();
    }

    function getTokenInfo(uint256 tokenId_) external override view returns (uint256, uint256, uint256, uint256, string memory, string memory, address, bool) {
        Token storage _info = _tokens[tokenId_];
        address owner = ownerOf(tokenId_);

        return (
            _info.value,
            _info.maturity,
            _info.interestRate,
            _info.advanceRate,
            _info.rating,
            _info._hash,
            owner,
            _info.redeemed
        );
    }

    function markAsRedeemed(uint256 tokenId) external override {
        require(ownerOf(tokenId) == msg.sender, "Only the owner can consume the asset");
        _tokens[tokenId].redeemed = true;
    }

    function addRiskItem(string memory rating, uint256 interestRate, uint256 advanceRate) external onlyOwner {
        riskModel.set(rating, interestRate, advanceRate);
    }

    function updateRiskItem(string memory rating, uint256 interestRate, uint256 advanceRate) external onlyOwner {
        riskModel.set(rating, interestRate, advanceRate);
    }

    function removeRiskItem(string memory rating) external onlyOwner {
        riskModel.remove(rating);
    }

    function getRiskItem(string calldata rating) external view returns (Risk.RiskItem memory) {
        return riskModel.riskItems[rating];
    }
}
