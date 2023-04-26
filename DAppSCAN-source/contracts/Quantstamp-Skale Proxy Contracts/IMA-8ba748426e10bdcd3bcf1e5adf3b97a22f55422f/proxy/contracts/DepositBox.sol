// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   DepositBox.sol - SKALE Interchain Messaging Agent
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
import "./interfaces/IMessageProxy.sol";
import "./interfaces/IERC20Module.sol";
import "./interfaces/IERC721Module.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721.sol";

interface ILockAndDataDB {
    function setContract(string calldata contractName, address newContract) external;
    function tokenManagerAddresses(bytes32 schainHash) external returns (address);
    function sendEth(address to, uint256 amount) external returns (bool);
    function approveTransfer(address to, uint256 amount) external;
    function addSchain(string calldata schainID, address tokenManagerAddress) external;
    function receiveEth(address from) external payable;
}

// This contract runs on the main net and accepts deposits


contract DepositBox is PermissionsForMainnet {

    enum TransactionOperation {
        transferETH,
        transferERC20,
        transferERC721,
        rawTransferERC20,
        rawTransferERC721
    }

    uint256 public constant GAS_AMOUNT_POST_MESSAGE = 200000;
    uint256 public constant AVERAGE_TX_PRICE = 10000000000;

    event MoneyReceivedMessage(
        address sender,
        string fromSchainID,
        address to,
        uint256 amount,
        bytes data
    );

    event Error(
        address to,
        uint256 amount,
        string message
    );

    modifier rightTransaction(string memory schainID) {
        bytes32 schainHash = keccak256(abi.encodePacked(schainID));
        address tokenManagerAddress = ILockAndDataDB(lockAndDataAddress_).tokenManagerAddresses(schainHash);
        require(schainHash != keccak256(abi.encodePacked("Mainnet")), "SKALE chain name is incorrect");
        require(tokenManagerAddress != address(0), "Unconnected chain");
        _;
    }

    modifier requireGasPayment() {
        require(msg.value >= GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE, "Gas was not paid");
        _;
        ILockAndDataDB(lockAndDataAddress_).receiveEth.value(msg.value)(msg.sender);
    }

    fallback() external payable {
        revert("Not allowed. in DepositBox");
    }

    function depositWithoutData(string calldata schainID, address to) external payable {
        deposit(schainID, to);
    }

    function depositERC20(
        string calldata schainID,
        address contractHere,
        address to,
        uint256 amount
    )
        external
        payable
        rightTransaction(schainID)
    {
        bytes32 schainHash = keccak256(abi.encodePacked(schainID));
        address tokenManagerAddress = ILockAndDataDB(lockAndDataAddress_).tokenManagerAddresses(schainHash);
        address lockAndDataERC20 = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("LockAndDataERC20"))
        );
        address erc20Module = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("ERC20Module"))
        );
        address proxyAddress = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("MessageProxy"))
        );
        require(
            IERC20(contractHere).allowance(
                msg.sender,
                address(this)
            ) >= amount,
            "Not allowed ERC20 Token"
        );
        require(
            IERC20(contractHere).transferFrom(
                msg.sender,
                lockAndDataERC20,
                amount
            ),
            "Could not transfer ERC20 Token"
        );
        bytes memory data = IERC20Module(erc20Module).receiveERC20(
            contractHere,
            to,
            amount,
            false);
        IMessageProxy(proxyAddress).postOutgoingMessage(
            schainID,
            tokenManagerAddress,
            msg.value,
            address(0),
            data
        );
        if (msg.value > 0) {
            ILockAndDataDB(lockAndDataAddress_).receiveEth.value(msg.value)(msg.sender);
        }
    }

    function rawDepositERC20(
        string calldata schainID,
        address contractHere,
        address contractThere,
        address to,
        uint256 amount
    )
        external
        payable
        rightTransaction(schainID)
    {
        address tokenManagerAddress = ILockAndDataDB(lockAndDataAddress_).tokenManagerAddresses(
            keccak256(abi.encodePacked(schainID))
        );
        address lockAndDataERC20 = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("LockAndDataERC20"))
        );
        address erc20Module = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("ERC20Module"))
        );
        require(
            IERC20(contractHere).allowance(
                msg.sender,
                address(this)
            ) >= amount, "Not allowed ERC20 Token"
        );
        require(
            IERC20(contractHere).transferFrom(
                msg.sender,
                lockAndDataERC20,
                amount
            ), "Could not transfer ERC20 Token"
        );
        bytes memory data = IERC20Module(erc20Module).receiveERC20(contractHere, to, amount, true);
        IMessageProxy(IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("MessageProxy"))
        )).postOutgoingMessage(
            schainID,
            tokenManagerAddress,
            msg.value,
            contractThere,
            data
        );
        if (msg.value > 0) {
            ILockAndDataDB(lockAndDataAddress_).receiveEth.value(msg.value)(msg.sender);
        }
    }

    function depositERC721(
        string calldata schainID,
        address contractHere,
        address to,
        uint256 tokenId) external payable rightTransaction(schainID)
        {
        bytes32 schainHash = keccak256(abi.encodePacked(schainID));
        address lockAndDataERC721 = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("LockAndDataERC721"))
        );
        address erc721Module = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("ERC721Module"))
        );
        address proxyAddress = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("MessageProxy"))
        );
        require(IERC721(contractHere).ownerOf(tokenId) == address(this), "Not allowed ERC721 Token");
        IERC721(contractHere).transferFrom(address(this), lockAndDataERC721, tokenId);
        require(IERC721(contractHere).ownerOf(tokenId) == lockAndDataERC721, "Did not transfer ERC721 token");
        bytes memory data = IERC721Module(erc721Module).receiveERC721(
            contractHere,
            to,
            tokenId,
            false);
        IMessageProxy(proxyAddress).postOutgoingMessage(
            schainID,
            ILockAndDataDB(lockAndDataAddress_).tokenManagerAddresses(schainHash),
            msg.value,
            address(0),
            data
        );
        if (msg.value > 0) {
            ILockAndDataDB(lockAndDataAddress_).receiveEth.value(msg.value)(msg.sender);
        }
    }

    function rawDepositERC721(
        string calldata schainID,
        address contractHere,
        address contractThere,
        address to,
        uint256 tokenId
    )
        external
        payable
        rightTransaction(schainID)
    {
        bytes32 schainHash = keccak256(abi.encodePacked(schainID));
        address lockAndDataERC721 = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("LockAndDataERC721"))
        );
        address erc721Module = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("ERC721Module"))
        );
        require(IERC721(contractHere).ownerOf(tokenId) == address(this), "Not allowed ERC721 Token");
        IERC721(contractHere).transferFrom(address(this), lockAndDataERC721, tokenId);
        require(IERC721(contractHere).ownerOf(tokenId) == lockAndDataERC721, "Did not transfer ERC721 token");
        bytes memory data = IERC721Module(erc721Module).receiveERC721(
            contractHere,
            to,
            tokenId,
            true);
        IMessageProxy(IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("MessageProxy"))
        )).postOutgoingMessage(
            schainID,
            ILockAndDataDB(lockAndDataAddress_).tokenManagerAddresses(schainHash),
            msg.value,
            contractThere,
            data
        );
        if (msg.value > 0) {
            ILockAndDataDB(lockAndDataAddress_).receiveEth.value(msg.value)(msg.sender);
        }
    }

    function postMessage(
        address sender,
        string calldata fromSchainID,
        address payable to,
        uint256 amount,
        bytes calldata data
    )
        external
    {
        require(data.length != 0, "Invalid data");
        address proxyAddress = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("MessageProxy"))
        );
        require(msg.sender == proxyAddress, "Incorrect sender");
        bytes32 schainHash = keccak256(abi.encodePacked(fromSchainID));
        require(
            schainHash != keccak256(abi.encodePacked("Mainnet")) &&
            sender == ILockAndDataDB(lockAndDataAddress_).tokenManagerAddresses(schainHash),
            "Receiver chain is incorrect"
        );
        require(
            amount <= address(lockAndDataAddress_).balance ||
            amount >= GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE,
            "Not enough money to finish this transaction"
        );
        require(
            ILockAndDataDB(lockAndDataAddress_).sendEth(getOwner(), GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE),
            "Could not send money to owner"
        );
        _executePerOperation(to, amount, data);
    }

    /// Create a new deposit box
    function initialize(address newLockAndDataAddress) public override initializer {
        PermissionsForMainnet.initialize(newLockAndDataAddress);
    }

    function deposit(string memory schainID, address to) public payable {
        bytes memory empty = "";
        deposit(schainID, to, empty);
    }

    function deposit(string memory schainID, address to, bytes memory data)
        public
        payable
        rightTransaction(schainID)
        requireGasPayment
    {
        bytes32 schainHash = keccak256(abi.encodePacked(schainID));
        address tokenManagerAddress = ILockAndDataDB(lockAndDataAddress_).tokenManagerAddresses(schainHash);
        address proxyAddress = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("MessageProxy"))
        );
        bytes memory newData;
        newData = abi.encodePacked(bytes1(uint8(1)), data);
        IMessageProxy(proxyAddress).postOutgoingMessage(
            schainID,
            tokenManagerAddress,
            msg.value,
            to,
            newData
        );
    }

    function _executePerOperation(
        address payable to,
        uint256 amount,
        bytes calldata data    
    )
        internal
    {
        TransactionOperation operation = _fallbackOperationTypeConvert(data);
        if (operation == TransactionOperation.transferETH) {
            if (amount > GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE) {
                ILockAndDataDB(lockAndDataAddress_).approveTransfer(
                    to,
                    amount - GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE
                );
            }
        } else if ((operation == TransactionOperation.transferERC20 && to == address(0)) ||
                  (operation == TransactionOperation.rawTransferERC20 && to != address(0))) {
            address erc20Module = IContractManagerForMainnet(lockAndDataAddress_).permitted(
                keccak256(abi.encodePacked("ERC20Module"))
            );
            require(IERC20Module(erc20Module).sendERC20(to, data), "Sending of ERC20 was failed");
            address receiver = IERC20Module(erc20Module).getReceiver(data);
            if (amount > GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE) {
                ILockAndDataDB(lockAndDataAddress_).approveTransfer(
                    receiver,
                    amount - GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE
                );
            }
        } else if ((operation == TransactionOperation.transferERC721 && to == address(0)) ||
                  (operation == TransactionOperation.rawTransferERC721 && to != address(0))) {
            address erc721Module = IContractManagerForMainnet(lockAndDataAddress_).permitted(
                keccak256(abi.encodePacked("ERC721Module"))
            );
            require(IERC721Module(erc721Module).sendERC721(to, data), "Sending of ERC721 was failed");
            address receiver = IERC721Module(erc721Module).getReceiver(to, data);
            if (amount > GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE) {
                ILockAndDataDB(lockAndDataAddress_).approveTransfer(
                    receiver,
                    amount - GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE
                );
            }
        }
    }

    /**
     * @dev Convert first byte of data to Operation
     * 0x01 - transfer eth
     * 0x03 - transfer ERC20 token
     * 0x05 - transfer ERC721 token
     * 0x13 - transfer ERC20 token - raw mode
     * 0x15 - transfer ERC721 token - raw mode
     * @param data - received data
     * @return operation
     */
    function _fallbackOperationTypeConvert(bytes memory data)
        private
        pure
        returns (TransactionOperation)
    {
        bytes1 operationType;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            operationType := mload(add(data, 0x20))
        }
        require(
            operationType == 0x01 ||
            operationType == 0x03 ||
            operationType == 0x05 ||
            operationType == 0x13 ||
            operationType == 0x15,
            "Operation type is not identified"
        );
        if (operationType == 0x01) {
            return TransactionOperation.transferETH;
        } else if (operationType == 0x03) {
            return TransactionOperation.transferERC20;
        } else if (operationType == 0x05) {
            return TransactionOperation.transferERC721;
        } else if (operationType == 0x13) {
            return TransactionOperation.rawTransferERC20;
        } else if (operationType == 0x15) {
            return TransactionOperation.rawTransferERC721;
        }
    }
}