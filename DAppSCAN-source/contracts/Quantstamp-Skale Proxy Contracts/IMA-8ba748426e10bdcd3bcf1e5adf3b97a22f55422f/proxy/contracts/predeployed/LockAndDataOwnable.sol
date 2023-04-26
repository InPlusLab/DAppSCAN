// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   LockAndDataOwnable.sol - SKALE Interchain Messaging Agent
 *   Copyright (C) 2019-Present SKALE Labs
 *   @author Sergiy Lavrynenko
 *
 *   SKALE IMA is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as published
 *   by the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   SKALE IMA is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with SKALE IMA.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma solidity 0.6.12;

import "./SkaleFeatures.sol";


/**
 * @title LockAndDataOwnable
 * @dev The LockAndDataOwnable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract LockAndDataOwnable {

    /**
     * @dev _ownerAddress is only used after transferOwnership(). 
     * By default, value of "skaleConfig.contractSettings.IMA._ownerAddress" config variable is used
     */
    address private _ownerAddress;


    /**
     * @dev The LockAndDataOwnable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() public {
        _ownerAddress = msg.sender;
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address payable newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner has to be set");
        setOwner(newOwner);
    }

    /**
     * @dev Sets new owner address.
     */
    function setOwner( address newAddressOwner ) public {
        _ownerAddress = newAddressOwner;
    }

    /**
     * @dev Returns owner address.
     */
    function getOwner() public view returns ( address ow ) {
        if ((_ownerAddress) == (address(0)) )
            return SkaleFeatures(0x00c033b369416c9ecd8e4a07aafa8b06b4107419e2).getConfigVariableAddress(
                "skaleConfig.contractSettings.IMA.lockAndDataAddress"
            );
        return _ownerAddress;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == getOwner(), "Only owner can execute this method");
        _;
    }

}
