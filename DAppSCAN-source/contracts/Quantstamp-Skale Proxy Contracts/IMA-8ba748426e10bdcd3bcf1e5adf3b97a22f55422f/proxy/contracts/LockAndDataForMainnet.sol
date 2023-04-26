// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   LockAndDataForMainnet.sol - SKALE Interchain Messaging Agent
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

import "./OwnableForMainnet.sol";

/**
 * @title Lock and Data For Mainnet
 * @dev Runs on Mainnet, holds deposited ETH, and contains mappings and
 * balances of ETH tokens received through DepositBox.
 */
contract LockAndDataForMainnet is OwnableForMainnet {

    mapping(bytes32 => address) public permitted;

    mapping(bytes32 => address) public tokenManagerAddresses;

    mapping(address => uint256) public approveTransfers;

    mapping(address => bool) public authorizedCaller;

    modifier allow(string memory contractName) {
        require(
            permitted[keccak256(abi.encodePacked(contractName))] == msg.sender ||
            getOwner() == msg.sender,
            "Not allowed"
        );
        _;
    }

    /**
     * @dev Emitted when DepositBox receives ETH.
     */
    event ETHReceived(address from, uint256 amount);

    /**
     * @dev Emitted upon failure.
     */
    event Error(
        address to,
        uint256 amount,
        string message
    );

    /**
     * @dev Allows DepositBox to receive ETH.
     *
     * Emits a {ETHReceived} event.
     */
    function receiveEth(address from) external allow("DepositBox") payable {
        emit ETHReceived(from, msg.value);
    }
    
    /**
     * @dev Allows Owner to set a new contract address.
     *
     * Requirements:
     *
     * - New contract address must be non-zero.
     * - New contract address must not already be added.
     * - Contract must contain code.
     */
    function setContract(string calldata contractName, address newContract) external virtual onlyOwner {
        require(newContract != address(0), "New address is equal zero");
        bytes32 contractId = keccak256(abi.encodePacked(contractName));
        require(permitted[contractId] != newContract, "Contract is already added");
        uint256 length;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            length := extcodesize(newContract)
        }
        require(length > 0, "Given contract address does not contain code");
        permitted[contractId] = newContract;
    }

    /**
     * @dev Adds a SKALE chain and its TokenManager address to
     * LockAndDataForMainnet.
     *
     * Requirements:
     *
     * - `msg.sender` must be authorized caller.
     * - SKALE chain must not already be added.
     * - TokenManager address must be non-zero.
     */
    function addSchain(string calldata schainID, address tokenManagerAddress) external {
        require(authorizedCaller[msg.sender], "Not authorized caller");
        bytes32 schainHash = keccak256(abi.encodePacked(schainID));
        require(tokenManagerAddresses[schainHash] == address(0), "SKALE chain is already set");
        require(tokenManagerAddress != address(0), "Incorrect Token Manager address");
        tokenManagerAddresses[schainHash] = tokenManagerAddress;
    }

    /**
     * @dev Allows Owner to remove a SKALE chain from contract.
     *
     * Requirements:
     *
     * - SKALE chain must already be set.
     */
    function removeSchain(string calldata schainID) external onlyOwner {
        bytes32 schainHash = keccak256(abi.encodePacked(schainID));
        require(tokenManagerAddresses[schainHash] != address(0), "SKALE chain is not set");
        delete tokenManagerAddresses[schainHash];
    }

    /**
     * @dev Allows Owner to add an authorized caller.
     */
    function addAuthorizedCaller(address caller) external onlyOwner {
        authorizedCaller[caller] = true;
    }

    /**
     * @dev Allows Owner to remove an authorized caller.
     */
    function removeAuthorizedCaller(address caller) external onlyOwner {
        authorizedCaller[caller] = false;
    }

    /**
     * @dev Allows DepositBox to approve transfer.
     */
    function approveTransfer(address to, uint256 amount) external allow("DepositBox") {
        approveTransfers[to] += amount;
    }

    /**
     * @dev Transfers a user's ETH.
     *
     * Requirements:
     *
     * - LockAndDataForMainnet must have sufficient ETH.
     * - User must be approved for ETH transfer.
     */
    function getMyEth() external {
        require(
            address(this).balance >= approveTransfers[msg.sender],
            "Not enough ETH. in `LockAndDataForMainnet.getMyEth`"
        );
        require(approveTransfers[msg.sender] > 0, "User has insufficient ETH");
        uint256 amount = approveTransfers[msg.sender];
        approveTransfers[msg.sender] = 0;
        msg.sender.transfer(amount);
    }

    /**
     * @dev Allows DepositBox to send ETH.
     *
     * Emits an {Error} upon insufficient ETH in LockAndDataForMainnet.
     */
    function sendEth(address payable to, uint256 amount) external allow("DepositBox") returns (bool) {
        if (address(this).balance >= amount) {
            to.transfer(amount);
            return true;
        }
    }

    /**
     * @dev Returns the contract address for a given contractName.
     */
    function getContract(string memory contractName) external view returns (address) {
        return permitted[keccak256(abi.encodePacked(contractName))];
    }

    /**
     * @dev Checks whether LockAndDataforMainnet is connected to a SKALE chain.
     */
    function hasSchain( string calldata schainID ) external view returns (bool) {
        bytes32 schainHash = keccak256(abi.encodePacked(schainID));
        if ( tokenManagerAddresses[schainHash] == address(0) ) {
            return false;
        }
        return true;
    }

    function initialize() public override initializer {
        OwnableForMainnet.initialize();
        authorizedCaller[msg.sender] = true;
    }
}
