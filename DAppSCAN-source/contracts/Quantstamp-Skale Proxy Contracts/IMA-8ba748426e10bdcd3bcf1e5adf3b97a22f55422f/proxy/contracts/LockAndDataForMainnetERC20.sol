// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   LockAndDataForMainnetERC20.sol - SKALE Interchain Messaging Agent
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


import "./PermissionsForMainnet.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

/**
 * @title Lock and Data For Mainnet ERC20
 * @dev Runs on Mainnet, holds deposited ERC20s, and contains mappings and
 * balances of ERC20 tokens received through DepositBox.
 */
contract LockAndDataForMainnetERC20 is PermissionsForMainnet {

    mapping(uint256 => address) public erc20Tokens;
    mapping(address => uint256) public erc20Mapper;
    uint256 public newIndexERC20;

    /**
     * @dev Allows ERC20Module to send an ERC20 token from
     * LockAndDataForMainnetERC20.
     * 
     * Requirements:
     *
     * - `amount` must be less than or equal to the balance
     * in LockAndDataForMainnetERC20.
     * - Transfer must be successful. 
     */
    function sendERC20(address contractHere, address to, uint256 amount) external allow("ERC20Module") returns (bool) {
        require(IERC20(contractHere).balanceOf(address(this)) >= amount, "Not enough money");
        require(IERC20(contractHere).transfer(to, amount), "something went wrong with `transfer` in ERC20");
        return true;
    }

    /**
     * @dev Allows ERC20Module to add an ERC20 token to LockAndDataForMainnetERC20.
     */
    function addERC20Token(address addressERC20) external allow("ERC20Module") returns (uint256) {
        uint256 index = newIndexERC20;
        erc20Tokens[index] = addressERC20;
        erc20Mapper[addressERC20] = index;
        newIndexERC20++;
        return index;
    }

    function initialize(address newLockAndDataAddress) public override initializer {
        PermissionsForMainnet.initialize(newLockAndDataAddress);
        newIndexERC20 = 1;
    }
}
