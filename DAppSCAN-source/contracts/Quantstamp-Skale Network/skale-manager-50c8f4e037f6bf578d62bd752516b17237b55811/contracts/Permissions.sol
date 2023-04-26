/*
    Permissions.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Artem Payvin

    SKALE Manager is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE Manager is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE Manager.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity ^0.5.3;

import "./ContractManager.sol";


/**
 * @title Permissions - connected module for Upgradeable approach, knows ContractManager
 * @author Artem Payvin
 */
contract Permissions is Ownable {

    ContractManager contractManager;

    /**
     * @dev allow - throws if called by any account and contract other than the owner
     * or `contractName` contract
     * @param contractName - human readable name of contract
     */
    modifier allow(string memory contractName) {
        require(
            contractManager.contracts(keccak256(abi.encodePacked(contractName))) == msg.sender || isOwner(),
            "Message sender is invalid");
        _;
    }

    modifier allowTwo(string memory contractName1, string memory contractName2) {
        require(
            contractManager.contracts(keccak256(abi.encodePacked(contractName1))) == msg.sender ||
            contractManager.contracts(keccak256(abi.encodePacked(contractName2))) == msg.sender ||
            isOwner(),
            "Message sender is invalid");
        _;
    }

    modifier allowThree(string memory contractName1, string memory contractName2, string memory contractName3) {
        require(
            contractManager.contracts(keccak256(abi.encodePacked(contractName1))) == msg.sender ||
            contractManager.contracts(keccak256(abi.encodePacked(contractName2))) == msg.sender ||
            contractManager.contracts(keccak256(abi.encodePacked(contractName3))) == msg.sender ||
            isOwner(),
            "Message sender is invalid");
        _;
    }

    /**
     * @dev constructor - sets current address of ContractManager
     * @param newContractsAddress - current address of ContractManager
     */
    constructor(address newContractsAddress) public {
        contractManager = ContractManager(newContractsAddress);
    }
}
