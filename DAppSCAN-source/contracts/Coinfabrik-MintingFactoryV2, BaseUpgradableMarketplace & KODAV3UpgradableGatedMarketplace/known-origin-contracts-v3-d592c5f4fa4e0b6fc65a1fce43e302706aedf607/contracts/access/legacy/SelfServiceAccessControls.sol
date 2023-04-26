// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./ISelfServiceAccessControls.sol";

contract SelfServiceAccessControls is ISelfServiceAccessControls {

    // Simple map to only allow certain artist create editions at first
    mapping(address => bool) public allowedArtists;

    // When true any existing KO artist can mint their own editions
    bool public openToAllArtist = false;

    /**
     * @dev Controls is the contract is open to all
     * @dev Only callable from owner
     */
    function setOpenToAllArtist(bool _openToAllArtist) public {
        openToAllArtist = _openToAllArtist;
    }

    /**
     * @dev Controls who can call this contract
     * @dev Only callable from owner
     */
    function setAllowedArtist(address _artist, bool _allowed) public {
        allowedArtists[_artist] = _allowed;
    }

    /**
     * @dev Checks to see if the account can create editions
     */
    function isEnabledForAccount(address account) public override view returns (bool) {
        if (openToAllArtist) {
            return true;
        }
        return allowedArtists[account];
    }

}
