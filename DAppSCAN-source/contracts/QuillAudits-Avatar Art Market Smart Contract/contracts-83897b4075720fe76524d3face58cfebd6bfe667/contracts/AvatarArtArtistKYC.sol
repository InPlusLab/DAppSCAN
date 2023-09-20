// SPDX-License-Identifier: MIT
// SWC-102-Outdated Compiler Version: L3
pragma solidity ^0.8.0;

import "./core/Ownable.sol";
import "./interfaces/IAvatarArtArtistKYC.sol";

/**
* @dev Verify and unverify Artist KYC information
* This approvement will be used to verify KYC so that Artist can create their own NFTs
*/
// SWC-135-Code With No Effects: L12
contract AvatarArtArtistKYC is IAvatarArtArtistKYC, Ownable{
    mapping(address => bool) private _isVerifieds;
    
    function isVerified(address account) external override view returns(bool){
        return _isVerifieds[account];
    }
    
    /**
    * @dev Toogle artists' KYC verification status
    * Note that: Only owner can send request
     */
    function toggleVerify(address account) external onlyOwner{
        _isVerifieds[account] = !_isVerifieds[account];
    }
}