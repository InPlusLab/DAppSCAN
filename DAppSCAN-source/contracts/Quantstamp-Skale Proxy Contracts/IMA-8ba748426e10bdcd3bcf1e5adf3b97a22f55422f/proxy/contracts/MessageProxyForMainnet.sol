// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   MessageProxyForMainnet.sol - SKALE Interchain Messaging Agent
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
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

interface ContractReceiverForMainnet {
    function postMessage(
        address sender,
        string calldata schainID,
        address to,
        uint256 amount,
        bytes calldata data
    )
        external;
}

interface IContractManagerSkaleManager {
    function contracts(bytes32 contractID) external view returns(address);
}

interface ISchains {
    function verifySchainSignature(
        uint256 signA,
        uint256 signB,
        bytes32 hash,
        uint256 counter,
        uint256 hashA,
        uint256 hashB,
        string calldata schainName
    )
        external
        view
        returns (bool);
}

/**
 * @title Message Proxy for Mainnet
 * @dev Runs on Mainnet, contains functions to manage the incoming messages from
 * `dstChainID` and outgoing messages to `srcChainID`. Every SKALE chain with 
 * IMA is therefore connected to MessageProxyForMainnet.
 *
 * Messages from SKALE chains are signed using BLS threshold signatures from the
 * nodes in the chain. Since Ethereum Mainnet has no BLS public key, mainnet
 * messages do not need to be signed.
 */
contract MessageProxyForMainnet is Initializable {

    // 16 Agents
    // Synchronize time with time.nist.gov
    // Every agent checks if it is his time slot
    // Time slots are in increments of 10 seconds
    // At the start of his slot each agent:
    // For each connected schain:
    // Read incoming counter on the dst chain
    // Read outgoing counter on the src chain
    // Calculate the difference outgoing - incoming
    // Call postIncomingMessages function passing (un)signed message array

    // ID of this schain, Chain 0 represents ETH mainnet,

    struct OutgoingMessageData {
        string dstChain;
        bytes32 dstChainHash;
        uint256 msgCounter;
        address srcContract;
        address dstContract;
        address to;
        uint256 amount;
        bytes data;
        uint256 length;
    }

    struct ConnectedChainInfo {
        // message counters start with 0
        uint256 incomingMessageCounter;
        uint256 outgoingMessageCounter;
        bool inited;
    }

    struct Message {
        address sender;
        address destinationContract;
        address to;
        uint256 amount;
        bytes data;
    }

    struct Signature {
        uint256[2] blsSignature;
        uint256 hashA;
        uint256 hashB;
        uint256 counter;
    }

    string public chainID;
    // Owner of this chain. For mainnet, the owner is SkaleManager
    address public owner;
    address public contractManagerSkaleManager;
    uint256 private _idxHead;
    uint256 private _idxTail;

    mapping(address => bool) public authorizedCaller;
    mapping(bytes32 => ConnectedChainInfo) public connectedChains;
    mapping ( uint256 => OutgoingMessageData ) private _outgoingMessageData;

    /**
     * @dev Emitted for every outgoing message to `dstChain`.
     */
    event OutgoingMessage(
        string dstChain,
        bytes32 indexed dstChainHash,
        uint256 indexed msgCounter,
        address indexed srcContract,
        address dstContract,
        address to,
        uint256 amount,
        bytes data,
        uint256 length
    );

    event PostMessageError(
        uint256 indexed msgCounter,
        bytes32 indexed srcChainHash,
        address sender,
        string fromSchainID,
        address to,
        uint256 amount,
        bytes data,
        string message
    );

    /**
     * @dev Adds an authorized caller.
     * 
     * Requirements:
     * 
     * - `msg.sender` must be an owner.
     */
    function addAuthorizedCaller(address caller) external {
        require(msg.sender == owner, "Sender is not an owner");
        authorizedCaller[caller] = true;
    }

    /**
     * @dev Removes an authorized caller.
     * 
     * Requirements:
     * 
     * - `msg.sender` must be an owner.
     */
    function removeAuthorizedCaller(address caller) external {
        require(msg.sender == owner, "Sender is not an owner");
        authorizedCaller[caller] = false;
    }

    /**
     * @dev Adds a `newChainID`.
     * 
     * Requirements:
     * 
     * - `msg.sender` must be SKALE Node address.
     * - `newChainID` must not be "Mainnet".
     * - `newChainID` must not already be added.
     */
    function addConnectedChain(
        string calldata newChainID
    )
        external
    {
        require(authorizedCaller[msg.sender], "Not authorized caller");

        require(
            keccak256(abi.encodePacked(newChainID)) !=
            keccak256(abi.encodePacked("Mainnet")), "SKALE chain name is incorrect. Inside in MessageProxy");

        require(
            !connectedChains[keccak256(abi.encodePacked(newChainID))].inited,
            "Chain is already connected"
        );
        connectedChains[
            keccak256(abi.encodePacked(newChainID))
        ] = ConnectedChainInfo({
            incomingMessageCounter: 0,
            outgoingMessageCounter: 0,
            inited: true
        });
    }

    /**
     * @dev Removes connected chain from this contract.
     * 
     * Requirements:
     * 
     * - `msg.sender` must be owner.
     * - `newChainID` must be initialized.
     */
    function removeConnectedChain(string calldata newChainID) external {
        require(authorizedCaller[msg.sender], "Not authorized caller");

        require(
            connectedChains[keccak256(abi.encodePacked(newChainID))].inited,
            "Chain is not initialized"
        );
        delete connectedChains[keccak256(abi.encodePacked(newChainID))];
    }

    /**
     * @dev Posts message from this contract to `dstChainID` MessageProxy contract.
     * This is called by a smart contract to make a cross-chain call.
     * 
     * Requirements:
     * 
     * - `dstChainID` must be initialized.
     */
    function postOutgoingMessage(
        string calldata dstChainID,
        address dstContract,
        uint256 amount,
        address to,
        bytes calldata data
    )
        external
    {
        bytes32 dstChainHash = keccak256(abi.encodePacked(dstChainID));
        require(connectedChains[dstChainHash].inited, "Destination chain is not initialized");
        connectedChains[dstChainHash].outgoingMessageCounter++;
        _pushOutgoingMessageData(
            OutgoingMessageData(
                dstChainID,
                dstChainHash,
                connectedChains[dstChainHash].outgoingMessageCounter - 1,
                msg.sender,
                dstContract,
                to,
                amount,
                data,
                data.length
            )
        );
    }

    /**
     * @dev Posts incoming message from `srcChainID`. 
     * 
     * Requirements:
     * 
     * - `msg.sender` must be authorized caller.
     * - `srcChainID` must be initialized.
     * - `startingCounter` must be equal to the chain's incoming message counter.
     * - If destination chain is Mainnet, message signature must be valid.
     */
    function postIncomingMessages(
        string calldata srcChainID,
        uint256 startingCounter,
        Message[] calldata messages,
        Signature calldata sign,
        uint256 idxLastToPopNotIncluding
    )
        external
    {
        bytes32 srcChainHash = keccak256(abi.encodePacked(srcChainID));
        require(authorizedCaller[msg.sender], "Not authorized caller");
        require(connectedChains[srcChainHash].inited, "Chain is not initialized");
        require(
            startingCounter == connectedChains[srcChainHash].incomingMessageCounter,
            "Starning counter is not qual to incomin message counter");

        if (keccak256(abi.encodePacked(chainID)) == keccak256(abi.encodePacked("Mainnet"))) {
            _convertAndVerifyMessages(srcChainID, messages, sign);
        }

        for (uint256 i = 0; i < messages.length; i++) {
            try ContractReceiverForMainnet(messages[i].destinationContract).postMessage(
                messages[i].sender,
                srcChainID,
                messages[i].to,
                messages[i].amount,
                messages[i].data
            ) {
                ++startingCounter;
            } catch Error(string memory reason) {
                emit PostMessageError(
                    ++startingCounter,
                    srcChainHash,
                    messages[i].sender,
                    srcChainID,
                    messages[i].to,
                    messages[i].amount,
                    messages[i].data,
                    reason
                );
            }
        }
        connectedChains[keccak256(abi.encodePacked(srcChainID))].incomingMessageCounter += uint256(messages.length);
        _popOutgoingMessageData(idxLastToPopNotIncluding);
    }

    /**
     * @dev Increments incoming message counter. 
     * 
     * Note: Test function. TODO: remove in production.
     * 
     * Requirements:
     * 
     * - `msg.sender` must be owner.
     */
    function moveIncomingCounter(string calldata schainName) external {
        require(msg.sender == owner, "Sender is not an owner");
        connectedChains[keccak256(abi.encodePacked(schainName))].incomingMessageCounter++;
    }

    /**
     * @dev Sets the incoming and outgoing message counters to zero. 
     * 
     * Note: Test function. TODO: remove in production.
     * 
     * Requirements:
     * 
     * - `msg.sender` must be owner.
     */
    function setCountersToZero(string calldata schainName) external {
        require(msg.sender == owner, "Sender is not an owner");
        connectedChains[keccak256(abi.encodePacked(schainName))].incomingMessageCounter = 0;
        connectedChains[keccak256(abi.encodePacked(schainName))].outgoingMessageCounter = 0;
    }

    /**
     * @dev Checks whether chain is currently connected.
     * 
     * Note: Mainnet chain does not have a public key, and is implicitly 
     * connected to MessageProxy.
     * 
     * Requirements:
     * 
     * - `someChainID` must not be Mainnet.
     */
    function isConnectedChain(
        string calldata someChainID
    )
        external
        view
        returns (bool)
    {
        //require(msg.sender == owner); // todo: tmp!!!!!
        require(
            keccak256(abi.encodePacked(someChainID)) !=
            keccak256(abi.encodePacked("Mainnet")),
            "Schain id can not be equal Mainnet"); // main net does not have a public key and is implicitly connected
        if ( ! connectedChains[keccak256(abi.encodePacked(someChainID))].inited ) {
            return false;
        }
        return true;
    }

    function getOutgoingMessagesCounter(string calldata dstChainID)
        external
        view
        returns (uint256)
    {
        bytes32 dstChainHash = keccak256(abi.encodePacked(dstChainID));
        require(connectedChains[dstChainHash].inited, "Destination chain is not initialized");
        return connectedChains[dstChainHash].outgoingMessageCounter;
    }

    function getIncomingMessagesCounter(string calldata srcChainID)
        external
        view
        returns (uint256)
    {
        bytes32 srcChainHash = keccak256(abi.encodePacked(srcChainID));
        require(connectedChains[srcChainHash].inited, "Source chain is not initialized");
        return connectedChains[srcChainHash].incomingMessageCounter;
    }

    /// Create a new message proxy

    function initialize(string memory newChainID, address newContractManager) public initializer {
        owner = msg.sender;
        authorizedCaller[msg.sender] = true;
        chainID = newChainID;
        contractManagerSkaleManager = newContractManager;
    }

    /**
     * @dev Checks whether outgoing message is valid.
     */
    function verifyOutgoingMessageData(
        uint256 idxMessage,
        address sender,
        address destinationContract,
        address to,
        uint256 amount
    )
        public
        view
        returns (bool isValidMessage)
    {
        isValidMessage = false;
        OutgoingMessageData memory d = _outgoingMessageData[idxMessage];
        if ( d.dstContract == destinationContract && d.srcContract == sender && d.to == to && d.amount == amount )
            isValidMessage = true;
    }

    function _convertAndVerifyMessages(
        string calldata srcChainID,
        Message[] calldata messages,
        Signature calldata sign
    )
        internal
    {
        Message[] memory input = new Message[](messages.length);
        for (uint256 i = 0; i < messages.length; i++) {
            input[i].sender = messages[i].sender;
            input[i].destinationContract = messages[i].destinationContract;
            input[i].to = messages[i].to;
            input[i].amount = messages[i].amount;
            input[i].data = messages[i].data;
        }
        require(
            _verifyMessageSignature(
                sign.blsSignature,
                _hashedArray(input),
                sign.counter,
                sign.hashA,
                sign.hashB,
                srcChainID
            ), "Signature is not verified"
        );
    }

    /**
     * @dev Checks whether message BLS signature is valid.
     */
    function _verifyMessageSignature(
        uint256[2] memory blsSignature,
        bytes32 hash,
        uint256 counter,
        uint256 hashA,
        uint256 hashB,
        string memory srcChainID
    )
        private
        view
        returns (bool)
    {
        address skaleSchains = IContractManagerSkaleManager(contractManagerSkaleManager).contracts(
            keccak256(abi.encodePacked("Schains"))
        );
        return ISchains(skaleSchains).verifySchainSignature(
            blsSignature[0],
            blsSignature[1],
            hash,
            counter,
            hashA,
            hashB,
            srcChainID
        );
    }

    /**
     * @dev Returns hash of message array.
     */
    function _hashedArray(Message[] memory messages) private pure returns (bytes32) {
        bytes memory data;
        for (uint256 i = 0; i < messages.length; i++) {
            data = abi.encodePacked(
                data,
                bytes32(bytes20(messages[i].sender)),
                bytes32(bytes20(messages[i].destinationContract)),
                bytes32(bytes20(messages[i].to)),
                messages[i].amount,
                messages[i].data
            );
        }
        return keccak256(data);
    }

    /**
     * @dev Push outgoing message into outgoingMessageData array.
     * 
     * Emits an {OutgoingMessage} event.
     */
    function _pushOutgoingMessageData( OutgoingMessageData memory d ) private {
        emit OutgoingMessage(
            d.dstChain,
            d.dstChainHash,
            d.msgCounter,
            d.srcContract,
            d.dstContract,
            d.to,
            d.amount,
            d.data,
            d.length
        );
        _outgoingMessageData[_idxTail] = d;
        ++_idxTail;
    }

    /**
     * @dev Pop outgoing message from outgoingMessageData array.
     */
    function _popOutgoingMessageData( uint256 idxLastToPopNotIncluding ) private returns ( uint256 cntDeleted ) {
        cntDeleted = 0;
        for ( uint256 i = _idxHead; i < idxLastToPopNotIncluding; ++ i ) {
            if ( i >= _idxTail )
                break;
            delete _outgoingMessageData[i];
            ++ cntDeleted;
        }
        if (cntDeleted > 0)
            _idxHead += cntDeleted;
    }
}
