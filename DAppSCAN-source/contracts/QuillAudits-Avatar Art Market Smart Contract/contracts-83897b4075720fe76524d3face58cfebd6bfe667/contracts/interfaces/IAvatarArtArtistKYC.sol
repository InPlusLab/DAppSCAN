// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAvatarArtArtistKYC{
    function isVerified(address account) external view returns(bool); 
}