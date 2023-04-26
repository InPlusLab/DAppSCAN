/*
    NodesFunctionality.sol - SKALE Manager
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

pragma solidity 0.5.16;

import "./Permissions.sol";
import "./interfaces/IConstants.sol";
import "./interfaces/INodesData.sol";
import "./interfaces/INodesFunctionality.sol";
import "./delegation/ValidatorService.sol";
import "./NodesData.sol";


/**
 * @title NodesFunctionality - contract contains all functionality logic to manage Nodes
 */
contract NodesFunctionality is Permissions, INodesFunctionality {

    // informs that Node is created
    event NodeCreated(
        uint nodeIndex,
        address owner,
        string name,
        bytes4 ip,
        bytes4 publicIP,
        uint16 port,
        uint16 nonce,
        uint32 time,
        uint gasSpend
    );

    // informs that node is fully finished quitting from the system
    event ExitCompleted(
        uint nodeIndex,
        address owner,
        uint32 time,
        uint gasSpend
    );

    // informs that owner starts the procedure of quitting the Node from the system
    event ExitInited(
        uint nodeIndex,
        address owner,
        uint32 startLeavingPeriod,
        uint32 time,
        uint gasSpend
    );

    /**
     * @dev createNode - creates new Node and add it to the NodesData contract
     * function could be only run by SkaleManager
     * @param from - owner of Node
     * @param data - Node's data
     * @return nodeIndex - index of Node
     */
    function createNode(address from, bytes calldata data) external allow("SkaleManager") returns (uint nodeIndex) {
        address nodesDataAddress = contractManager.getContract("NodesData");
        uint16 nonce;
        bytes4 ip;
        bytes4 publicIP;
        uint16 port;
        string memory name;
        bytes memory publicKey;

        // decode data from the bytes
        (port, nonce, ip, publicIP) = fallbackDataConverter(data);
        (publicKey, name) = fallbackDataConverterPublicKeyAndName(data);

        // checks that Node has correct data
        require(ip != 0x0 && !INodesData(nodesDataAddress).nodesIPCheck(ip), "IP address is zero or is not available");
        require(!INodesData(nodesDataAddress).nodesNameCheck(keccak256(abi.encodePacked(name))), "Name has already registered");
        require(port > 0, "Port is zero");

        uint validatorId = ValidatorService(contractManager.getContract("ValidatorService")).getValidatorIdByNodeAddress(from);

        // adds Node to NodesData contract
        nodeIndex = INodesData(nodesDataAddress).addNode(
            from,
            name,
            ip,
            publicIP,
            port,
            publicKey,
            validatorId);
        // adds Node to Fractional Nodes or to Full Nodes
        // setNodeType(nodesDataAddress, constantsAddress, nodeIndex);

        emit NodeCreated(
            nodeIndex,
            from,
            name,
            ip,
            publicIP,
            port,
            nonce,
            uint32(block.timestamp),
            gasleft());
    }

    /**
     * @dev removeNode - delete Node
     * function could be only run by SkaleManager
     * @param from - owner of Node
     * @param nodeIndex - index of Node
     */
    function removeNode(address from, uint nodeIndex) external allow("SkaleManager") {
        address nodesDataAddress = contractManager.getContract("NodesData");

        require(INodesData(nodesDataAddress).isNodeExist(from, nodeIndex), "Node does not exist for message sender");
        require(INodesData(nodesDataAddress).isNodeActive(nodeIndex), "Node is not Active");

        INodesData(nodesDataAddress).setNodeLeft(nodeIndex);

        INodesData(nodesDataAddress).removeNode(nodeIndex);
    }

    function removeNodeByRoot(uint nodeIndex) external allow("SkaleManager") {
        address nodesDataAddress = contractManager.getContract("NodesData");
        INodesData(nodesDataAddress).setNodeLeft(nodeIndex);

        INodesData(nodesDataAddress).removeNode(nodeIndex);
    }

    /**
     * @dev initExit - initiate a procedure of quitting the system
     * function could be only run by SkaleManager
     * @param from - owner of Node
     * @param nodeIndex - index of Node
     * @return true - if everything OK
     */
    function initExit(address from, uint nodeIndex) external allow("SkaleManager") returns (bool) {
        NodesData nodesData = NodesData(contractManager.getContract("NodesData"));

        require(nodesData.isNodeExist(from, nodeIndex), "Node does not exist for message sender");

        nodesData.setNodeLeaving(nodeIndex);

        emit ExitInited(
            nodeIndex,
            from,
            uint32(block.timestamp),
            uint32(block.timestamp),
            gasleft());
        return true;
    }

    /**
     * @dev completeExit - finish a procedure of quitting the system
     * function could be run only by SkaleMManager
     * @param from - owner of Node
     * @param nodeIndex - index of Node
     * @return amount of SKL which be returned
     */
    function completeExit(address from, uint nodeIndex) external allow("SkaleManager") returns (bool) {
        NodesData nodesData = NodesData(contractManager.getContract("NodesData"));

        require(nodesData.isNodeExist(from, nodeIndex), "Node does not exist for message sender");
        require(nodesData.isNodeLeaving(nodeIndex), "Node is not Leaving");

        nodesData.setNodeLeft(nodeIndex);
        nodesData.removeNode(nodeIndex);

        emit ExitCompleted(
            nodeIndex,
            from,
            uint32(block.timestamp),
            gasleft());
        return true;
    }

    /**
     * @dev constructor in Permissions approach
     * @param _contractsAddress needed in Permissions constructor
    */
    function initialize(address _contractsAddress) public initializer {
        Permissions.initialize(_contractsAddress);
    }

    /**
     * @dev fallbackDataConverter - converts data from bytes to normal parameters
     * @param data - concatenated parameters
     * @return port
     * @return nonce
     * @return ip address
     * @return public ip address
     */
    function fallbackDataConverter(bytes memory data)
        private
        pure
        returns (uint16, uint16, bytes4, bytes4 /*address secondAddress,*/)
    {
        require(data.length > 77, "Incorrect bytes data config");

        bytes4 ip;
        bytes4 publicIP;
        bytes2 portInBytes;
        bytes2 nonceInBytes;
        assembly {
            portInBytes := mload(add(data, 33)) // 0x21
            nonceInBytes := mload(add(data, 35)) // 0x25
            ip := mload(add(data, 37)) // 0x29
            publicIP := mload(add(data, 41))
        }

        return (uint16(portInBytes), uint16(nonceInBytes), ip, publicIP);
    }

    /**
     * @dev fallbackDataConverterPublicKeyAndName - converts data from bytes to public key and name
     * @param data - concatenated public key and name
     * @return public key
     * @return name of Node
     */
    function fallbackDataConverterPublicKeyAndName(bytes memory data) private pure returns (bytes memory, string memory) {
        require(data.length > 77, "Incorrect bytes data config");
        bytes32 firstPartPublicKey;
        bytes32 secondPartPublicKey;
        bytes memory publicKey = new bytes(64);

        // convert public key
        assembly {
            firstPartPublicKey := mload(add(data, 45))
            secondPartPublicKey := mload(add(data, 77))
        }
        for (uint8 i = 0; i < 32; i++) {
            publicKey[i] = firstPartPublicKey[i];
        }
        for (uint8 i = 0; i < 32; i++) {
            publicKey[i + 32] = secondPartPublicKey[i];
        }

        // convert name
        string memory name = new string(data.length - 77);
        for (uint i = 0; i < bytes(name).length; ++i) {
            bytes(name)[i] = data[77 + i];
        }
        return (publicKey, name);
    }

}
