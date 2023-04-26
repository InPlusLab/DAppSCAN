// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   TokenManager.sol - SKALE Interchain Messaging Agent
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
import "./../interfaces/IMessageProxy.sol";
import "./../interfaces/IERC20Module.sol";
import "./../interfaces/IERC721Module.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721.sol";


interface ILockAndDataTM {
    function setContract(string calldata contractName, address newContract) external;
    function tokenManagerAddresses(bytes32 schainHash) external returns (address);
    function sendEth(address to, uint256 amount) external returns (bool);
    function receiveEth(address sender, uint256 amount) external returns (bool);
    function approveTransfer(address to, uint256 amount) external;
    function ethCosts(address to) external returns (uint256);
    function addGasCosts(address to, uint256 amount) external;
    function reduceGasCosts(address to, uint256 amount) external returns (bool);
    function removeGasCosts(address to) external returns (uint256);
}

// This contract runs on schains and accepts messages from main net creates ETH clones.
// When the user exits, it burns them

/**
 * @title Token Manager
 * @dev Runs on SKALE Chains, accepts messages from mainnet, and instructs
 * TokenFactory to create clones. TokenManager mints tokens via
 * LockAndDataForSchain*. When a user exits a SKALE chain, TokenFactory
 * burns tokens.
 */
contract TokenManager is PermissionsForSchain {


    enum TransactionOperation {
        transferETH,
        transferERC20,
        transferERC721,
        rawTransferERC20,
        rawTransferERC721
    }

    // ID of this schain,
    string private _chainID;
    address private _proxyForSchainAddress;

    uint256 public constant GAS_AMOUNT_POST_MESSAGE = 200000;
    uint256 public constant AVERAGE_TX_PRICE = 10000000000;

    modifier rightTransaction(string memory schainID) {
        bytes32 schainHash = keccak256(abi.encodePacked(schainID));
        address schainTokenManagerAddress = ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(schainHash);
        require(
            schainHash != keccak256(abi.encodePacked("Mainnet")),
            "This function is not for transfering to Mainnet"
        );
        require(schainTokenManagerAddress != address(0), "Incorrect Token Manager address");
        _;
    }

    modifier receivedEth(uint256 amount) {
        require(amount >= GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE, "Null Amount");
        require(ILockAndDataTM(getLockAndDataAddress()).receiveEth(msg.sender, amount), "Could not receive ETH Clone");
        _;
    }


    /// Create a new token manager

    constructor(
        string memory newChainID,
        address newProxyAddress,
        address newLockAndDataAddress
    )
        public
        PermissionsForSchain(newLockAndDataAddress)
    {
        _chainID = newChainID;
        _proxyForSchainAddress = newProxyAddress;
    }

    fallback() external payable {
        revert("Not allowed. in TokenManager");
    }

    function exitToMainWithoutData(address to, uint256 amount) external {
        exitToMain(to, amount);
    }

    function transferToSchainWithoutData(string calldata schainID, address to, uint256 amount) external {
        transferToSchain(schainID, to, amount);
    }

    /**
     * @dev Adds ETH cost to perform exit transaction.
     */
    function addEthCostWithoutAddress(uint256 amount) external {
        addEthCost(amount);
    }

    /**
     * @dev Deducts ETH cost to perform exit transaction.
     */
    function removeEthCost() external {
        uint256 returnBalance = ILockAndDataTM(getLockAndDataAddress()).removeGasCosts(msg.sender);
        require(ILockAndDataTM(getLockAndDataAddress()).sendEth(msg.sender, returnBalance), "Not sent");
    }

    function exitToMainERC20(address contractHere, address to, uint256 amount) external {
        address lockAndDataERC20 = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("LockAndDataERC20")));
        address erc20Module = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("ERC20Module")));
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
        require(
            ILockAndDataTM(getLockAndDataAddress()).reduceGasCosts(
                msg.sender,
                GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE),
            "Not enough gas sent");
        bytes memory data = IERC20Module(erc20Module).receiveERC20(
            contractHere,
            to,
            amount,
            false);
        IMessageProxy(getProxyForSchainAddress()).postOutgoingMessage(
            "Mainnet",
            ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(keccak256(abi.encodePacked("Mainnet"))),
            GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE,
            address(0),
            data
        );
    }

    function rawExitToMainERC20(
        address contractHere,
        address contractThere,
        address to,
        uint256 amount) external
        {
        address lockAndDataERC20 = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("LockAndDataERC20")));
        address erc20Module = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("ERC20Module")));
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
        require(
            ILockAndDataTM(getLockAndDataAddress()).reduceGasCosts(
                msg.sender,
                GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE),
            "Not enough gas sent");
        bytes memory data = IERC20Module(erc20Module).receiveERC20(
            contractHere,
            to,
            amount,
            true);
        IMessageProxy(getProxyForSchainAddress()).postOutgoingMessage(
            "Mainnet",
            ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(keccak256(abi.encodePacked("Mainnet"))),
            GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE,
            contractThere,
            data
        );
    }

    function transferToSchainERC20(
        string calldata schainID,
        address contractHere,
        address to,
        uint256 amount) external
        {
        address lockAndDataERC20 = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("LockAndDataERC20")));
        address erc20Module = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("ERC20Module")));
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
        IMessageProxy(getProxyForSchainAddress()).postOutgoingMessage(
            schainID,
            ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(keccak256(abi.encodePacked("Mainnet"))),
            0,
            address(0),
            data
        );
    }

    function rawTransferToSchainERC20(
        string calldata schainID,
        address contractHere,
        address contractThere,
        address to,
        uint256 amount) external
        {
        address lockAndDataERC20 = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("LockAndDataERC20")));
        address erc20Module = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("ERC20Module")));
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
            true);
        IMessageProxy(getProxyForSchainAddress()).postOutgoingMessage(
            schainID,
            ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(keccak256(abi.encodePacked("Mainnet"))),
            0,
            contractThere,
            data
        );
    }

    function exitToMainERC721(address contractHere, address to, uint256 tokenId) external {
        address lockAndDataERC721 = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("LockAndDataERC721")));
        address erc721Module = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("ERC721Module")));
        require(IERC721(contractHere).ownerOf(tokenId) == address(this), "Not allowed ERC721 Token");
        IERC721(contractHere).transferFrom(address(this), lockAndDataERC721, tokenId);
        require(IERC721(contractHere).ownerOf(tokenId) == lockAndDataERC721, "Did not transfer ERC721 token");
        require(
            ILockAndDataTM(getLockAndDataAddress()).reduceGasCosts(
                msg.sender,
                GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE),
            "Not enough gas sent");
        bytes memory data = IERC721Module(erc721Module).receiveERC721(
            contractHere,
            to,
            tokenId,
            false);
        IMessageProxy(getProxyForSchainAddress()).postOutgoingMessage(
            "Mainnet",
            ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(keccak256(abi.encodePacked("Mainnet"))),
            GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE,
            address(0),
            data
        );
    }

    function rawExitToMainERC721(
        address contractHere,
        address contractThere,
        address to,
        uint256 tokenId) external
        {
        address lockAndDataERC721 = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("LockAndDataERC721")));
        address erc721Module = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("ERC721Module")));
        require(IERC721(contractHere).ownerOf(tokenId) == address(this), "Not allowed ERC721 Token");
        IERC721(contractHere).transferFrom(address(this), lockAndDataERC721, tokenId);
        require(IERC721(contractHere).ownerOf(tokenId) == lockAndDataERC721, "Did not transfer ERC721 token");
        require(
            ILockAndDataTM(getLockAndDataAddress()).reduceGasCosts(
                msg.sender,
                GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE),
            "Not enough gas sent");
        bytes memory data = IERC721Module(erc721Module).receiveERC721(
            contractHere,
            to,
            tokenId,
            true);
        IMessageProxy(getProxyForSchainAddress()).postOutgoingMessage(
            "Mainnet",
            ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(keccak256(abi.encodePacked("Mainnet"))),
            GAS_AMOUNT_POST_MESSAGE * AVERAGE_TX_PRICE,
            contractThere,
            data
        );
    }

    function transferToSchainERC721(
        string calldata schainID,
        address contractHere,
        address to,
        uint256 tokenId) external
        {
        address lockAndDataERC721 = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("LockAndDataERC721")));
        address erc721Module = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("ERC721Module")));
        require(IERC721(contractHere).ownerOf(tokenId) == address(this), "Not allowed ERC721 Token");
        IERC721(contractHere).transferFrom(address(this), lockAndDataERC721, tokenId);
        require(IERC721(contractHere).ownerOf(tokenId) == lockAndDataERC721, "Did not transfer ERC721 token");
        bytes memory data = IERC721Module(erc721Module).receiveERC721(
            contractHere,
            to,
            tokenId,
            false);
        IMessageProxy(getProxyForSchainAddress()).postOutgoingMessage(
            schainID,
            ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(keccak256(abi.encodePacked("Mainnet"))),
            0,
            address(0),
            data
        );
    }

    function rawTransferToSchainERC721(
        string calldata schainID,
        address contractHere,
        address contractThere,
        address to,
        uint256 tokenId) external
        {
        address lockAndDataERC721 = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("LockAndDataERC721")));
        address erc721Module = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("ERC721Module")));
        require(IERC721(contractHere).ownerOf(tokenId) == address(this), "Not allowed ERC721 Token");
        IERC721(contractHere).transferFrom(address(this), lockAndDataERC721, tokenId);
        require(IERC721(contractHere).ownerOf(tokenId) == lockAndDataERC721, "Did not transfer ERC721 token");
        bytes memory data = IERC721Module(erc721Module).receiveERC721(
            contractHere,
            to,
            tokenId,
            true);
        IMessageProxy(getProxyForSchainAddress()).postOutgoingMessage(
            schainID,
            ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(keccak256(abi.encodePacked("Mainnet"))),
            0,
            contractThere,
            data
        );
    }

    /**
     * @dev Allows MessageProxy to post operational message from mainnet
     * or SKALE chains.
     * 
     * Emits an {Error} event upon failure.
     *
     * Requirements:
     * 
     * - MessageProxy must be the sender.
     * - `fromSchainID` must exist in TokenManager addresses.
     */
    function postMessage(
        address sender,
        string calldata fromSchainID,
        address to,
        uint256 amount,
        bytes calldata data
    )
        external
    {
        require(data.length != 0, "Invalid data");
        require(msg.sender == getProxyForSchainAddress(), "Not a sender");
        bytes32 schainHash = keccak256(abi.encodePacked(fromSchainID));
        require(
            schainHash != keccak256(abi.encodePacked(getChainID())) && 
            sender == ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(schainHash),
            "Receiver chain is incorrect"
        );

        TransactionOperation operation = _fallbackOperationTypeConvert(data);
        if (operation == TransactionOperation.transferETH) {
            require(to != address(0), "Incorrect receiver");
            require(ILockAndDataTM(getLockAndDataAddress()).sendEth(to, amount), "Not Sent");
        } else if ((operation == TransactionOperation.transferERC20 && to == address(0)) ||
                  (operation == TransactionOperation.rawTransferERC20 && to != address(0))) {
            address erc20Module = IContractManagerForSchain(
                getLockAndDataAddress()
            ).permitted(keccak256(abi.encodePacked("ERC20Module")));
            require(IERC20Module(erc20Module).sendERC20(to, data), "Failed to send ERC20");
            address receiver = IERC20Module(erc20Module).getReceiver(data);
            require(ILockAndDataTM(getLockAndDataAddress()).sendEth(receiver, amount), "Not Sent");
        } else if ((operation == TransactionOperation.transferERC721 && to == address(0)) ||
                  (operation == TransactionOperation.rawTransferERC721 && to != address(0))) {
            address erc721Module = IContractManagerForSchain(
                getLockAndDataAddress()
            ).permitted(keccak256(abi.encodePacked("ERC721Module")));
            require(IERC721Module(erc721Module).sendERC721(to, data), "Failed to send ERC721");
            address receiver = IERC721Module(erc721Module).getReceiver(to, data);
            require(ILockAndDataTM(getLockAndDataAddress()).sendEth(receiver, amount), "Not Sent");
        }
    }

    /**
     * @dev Performs an exit (post outgoing message) to Mainnet.
     */
    function exitToMain(address to, uint256 amount) public {
        bytes memory empty = "";
        exitToMain(to, amount, empty);
    }

    /**
     * @dev Performs an exit (post outgoing message) to Mainnet.
     */
    function exitToMain(address to, uint256 amount, bytes memory data) public receivedEth(amount) {
        bytes memory newData;
        newData = abi.encodePacked(bytes1(uint8(1)), data);
        IMessageProxy(getProxyForSchainAddress()).postOutgoingMessage(
            "Mainnet",
            ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(keccak256(abi.encodePacked("Mainnet"))),
            amount,
            to,
            newData
        );
    }

    function transferToSchain(string memory schainID, address to, uint256 amount) public {
        bytes memory data = "";
        transferToSchain(
            schainID,
            to,
            amount,
            data);
    }

    function transferToSchain(
        string memory schainID,
        address to,
        uint256 amount,
        bytes memory data
    )
        public
        rightTransaction(schainID)
        receivedEth(amount)
    {
        IMessageProxy(getProxyForSchainAddress()).postOutgoingMessage(
            schainID,
            ILockAndDataTM(getLockAndDataAddress()).tokenManagerAddresses(keccak256(abi.encodePacked(schainID))),
            amount,
            to,
            data
        );
    }

    /**
     * @dev Adds ETH cost for `msg.sender` exit transaction.
     */
    function addEthCost(uint256 amount) public {
        addEthCost(msg.sender, amount);
    }

    /**
     * @dev Adds ETH cost for user's exit transaction.
     */
    function addEthCost(address sender, uint256 amount) public receivedEth(amount) {
        ILockAndDataTM(getLockAndDataAddress()).addGasCosts(sender, amount);
    }

    /**
     * @dev Returns chain ID.
     */
    function getChainID() public view returns ( string memory cID ) {
        if ((keccak256(abi.encodePacked(_chainID))) == (keccak256(abi.encodePacked(""))) ) {
            return SkaleFeatures(0x00c033b369416c9ecd8e4a07aafa8b06b4107419e2)
                .getConfigVariableString("skaleConfig.sChain.schainID");
        }
        return _chainID;
    }

    /**
     * @dev Returns MessageProxy address.
     */
    function getProxyForSchainAddress() public view returns ( address ow ) { // l_sergiy: added
        if (_proxyForSchainAddress == address(0) ) {
            return SkaleFeatures(0x00c033b369416c9ecd8e4a07aafa8b06b4107419e2).getConfigVariableAddress(
                "skaleConfig.contractSettings.IMA.messageProxyAddress"
            );
        }
        return _proxyForSchainAddress;
    }

    /**
     * @dev Converts the first byte of data to an operation.
     * 
     * 0x01 - transfer ETH
     * 0x03 - transfer ERC20 token
     * 0x05 - transfer ERC721 token
     * 0x13 - transfer ERC20 token - raw mode
     * 0x15 - transfer ERC721 token - raw mode
     * 
     * Requirements:
     * 
     * - Operation must be one of the possible types.
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
