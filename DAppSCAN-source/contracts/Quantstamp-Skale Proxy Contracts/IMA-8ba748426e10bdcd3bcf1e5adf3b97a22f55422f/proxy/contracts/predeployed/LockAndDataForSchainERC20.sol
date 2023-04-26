// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   LockAndDataForSchainERC20.sol - SKALE Interchain Messaging Agent
 *   Copyright (C) 2019-Present SKALE Labs
 *   @author Artem Payvin
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

import "./PermissionsForSchain.sol";

interface ERC20MintAndBurn {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function balanceOf(address to) external view returns (uint256);
}

/**
 * @title Lock and Data For SKALE chain ERC20
 * @dev Runs on SKALE chains, holds deposited ERC20s, and contains mappings and
 * balances of ERC20 tokens received through DepositBox.
 */
contract LockAndDataForSchainERC20 is PermissionsForSchain {

    mapping(uint256 => address) public erc20Tokens;
    mapping(address => uint256) public erc20Mapper;

    /**
     * @dev Emitted upon minting on the SKALE chain.
     */
    event SentERC20(bool result);
    
    /**
     * @dev Emitted upon receipt in LockAndDataForSchainERC20.
     */
    event ReceivedERC20(bool result);

    constructor(address _lockAndDataAddress) public PermissionsForSchain(_lockAndDataAddress) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Allows ERC20Module to send (mint) ERC20 tokens from LockAndDataForSchainERC20.
     * 
     * Emits a {SentERC20} event.
     */
    function sendERC20(address contractHere, address to, uint256 amount) external allow("ERC20Module") returns (bool) {
        ERC20MintAndBurn(contractHere).mint(to, amount);
        emit SentERC20(true);
        return true;
    }

    /**
     * @dev Allows ERC20Module to receive ERC20 tokens to LockAndDataForSchainERC20.
     * 
     * Emits a {ReceivedERC20} event.
     * 
     * Requirements:
     * 
     * - `amount` must be less than or equal to the balance in
     * LockAndDataForSchainERC20.
     */
    function receiveERC20(address contractHere, uint256 amount) external allow("ERC20Module") returns (bool) {
        require(ERC20MintAndBurn(contractHere).balanceOf(address(this)) >= amount, "Amount not transfered");
        ERC20MintAndBurn(contractHere).burn(amount);
        emit ReceivedERC20(true);
        return true;
    }

    /**
     * @dev Allows ERC20Module to add an ERC20 token to LockAndDataForSchainERC20.
     */
    function addERC20Token(address addressERC20, uint256 contractPosition) external allow("ERC20Module") {
        erc20Tokens[contractPosition] = addressERC20;
        erc20Mapper[addressERC20] = contractPosition;
    }
}

