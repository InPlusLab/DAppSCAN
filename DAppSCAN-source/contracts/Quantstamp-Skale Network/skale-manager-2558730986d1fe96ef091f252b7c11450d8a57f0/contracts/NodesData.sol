/*
    NodesData.sol - SKALE Manager
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


/**
 * @title NodesData - Data contract for NodesFunctionality
 */
contract NodesData is INodesData, Permissions {

    // All Nodes states
    enum NodeStatus {Active, Leaving, Left}

    struct Node {
        string name;
        bytes4 ip;
        bytes4 publicIP;
        uint16 port;
        bytes publicKey;
        uint startBlock;
        uint32 lastRewardDate;
        // uint8 freeSpace;
        // uint indexInSpaceMap;
        //address secondAddress;
        uint32 finishTime;
        NodeStatus status;
        uint validatorId;
    }

    // struct to note which Nodes and which number of Nodes owned by user
    struct CreatedNodes {
        mapping (uint => bool) isNodeExist;
        uint numberOfNodes;
    }

    struct SpaceManaging {
        uint8 freeSpace;
        uint indexInSpaceMap;
    }

    // array which contain all Nodes
    Node[] public nodes;

    SpaceManaging[] public spaceOfNodes;

    // mapping for checking which Nodes and which number of Nodes owned by user
    mapping (address => CreatedNodes) public nodeIndexes;
    // mapping for checking is IP address busy
    mapping (bytes4 => bool) public nodesIPCheck;
    // mapping for checking is Name busy
    mapping (bytes32 => bool) public nodesNameCheck;
    // mapping for indication from Name to Index
    mapping (bytes32 => uint) public nodesNameToIndex;
    // mapping for indication from space to Nodes
    mapping (uint8 => uint[]) public spaceToNodes;

    uint public numberOfActiveNodes;
    uint public numberOfLeavingNodes;
    uint public numberOfLeftNodes;



    function getNodesWithFreeSpace(uint8 freeSpace) external view returns (uint[] memory) {
        uint[] memory nodesWithFreeSpace = new uint[](this.countNodesWithFreeSpace(freeSpace));
        uint cursor = 0;
        for (uint8 i = freeSpace; i <= 128; ++i) {
            for (uint j = 0; j < spaceToNodes[i].length; j++) {
                nodesWithFreeSpace[cursor] = spaceToNodes[i][j];
                ++cursor;
            }
        }
        return nodesWithFreeSpace;
    }

    function countNodesWithFreeSpace(uint8 freeSpace) external view returns (uint count) {
        count = 0;
        for (uint8 i = freeSpace; i <= 128; ++i) {
            count = count.add(spaceToNodes[i].length);
        }
    }

    /**
     * @dev addNode - adds Node to array
     * function could be run only by executor
     * @param from - owner of Node
     * @param name - Node name
     * @param ip - Node ip
     * @param publicIP - Node public ip
     * @param port - Node public port
     * @param publicKey - Ethereum public key
     * @return index of Node
     */
    function addNode(
        address from,
        string calldata name,
        bytes4 ip,
        bytes4 publicIP,
        uint16 port,
        bytes calldata publicKey,
        uint validatorId
    )
        external
        allow("NodesFunctionality")
        returns (uint nodeIndex)
    {
        nodes.push(Node({
            name: name,
            ip: ip,
            publicIP: publicIP,
            port: port,
            //owner: from,
            publicKey: publicKey,
            startBlock: block.number,
            lastRewardDate: uint32(block.timestamp),
            finishTime: 0,
            status: NodeStatus.Active,
            validatorId: validatorId
        }));
        nodeIndex = nodes.length - 1;
        bytes32 nodeId = keccak256(abi.encodePacked(name));
        nodesIPCheck[ip] = true;
        nodesNameCheck[nodeId] = true;
        nodesNameToIndex[nodeId] = nodeIndex;
        nodeIndexes[from].isNodeExist[nodeIndex] = true;
        nodeIndexes[from].numberOfNodes++;
        spaceOfNodes.push(SpaceManaging({
            freeSpace: 128,
            indexInSpaceMap: spaceToNodes[128].length
        }));
        spaceToNodes[128].push(nodeIndex);
        numberOfActiveNodes++;
    }

    /**
     * @dev setNodeLeaving - set Node Leaving
     * function could be run only by NodesFunctionality
     * @param nodeIndex - index of Node
     */
    function setNodeLeaving(uint nodeIndex) external allow("NodesFunctionality") {
        nodes[nodeIndex].status = NodeStatus.Leaving;
        numberOfActiveNodes--;
        numberOfLeavingNodes++;
    }

    /**
     * @dev setNodeLeft - set Node Left
     * function could be run only by NodesFunctionality
     * @param nodeIndex - index of Node
     */
    function setNodeLeft(uint nodeIndex) external allow("NodesFunctionality") {
        nodesIPCheck[nodes[nodeIndex].ip] = false;
        nodesNameCheck[keccak256(abi.encodePacked(nodes[nodeIndex].name))] = false;
        // address ownerOfNode = nodes[nodeIndex].owner;
        // nodeIndexes[ownerOfNode].isNodeExist[nodeIndex] = false;
        // nodeIndexes[ownerOfNode].numberOfNodes--;
        delete nodesNameToIndex[keccak256(abi.encodePacked(nodes[nodeIndex].name))];
        if (nodes[nodeIndex].status == NodeStatus.Active) {
            numberOfActiveNodes--;
        } else {
            numberOfLeavingNodes--;
        }
        nodes[nodeIndex].status = NodeStatus.Left;
        numberOfLeftNodes++;
    }

    function removeNode(uint nodeIndex) external allow("NodesFunctionality") {
        uint8 space = spaceOfNodes[nodeIndex].freeSpace;
        uint indexInArray = spaceOfNodes[nodeIndex].indexInSpaceMap;
        if (indexInArray < spaceToNodes[space].length - 1) {
            uint shiftedIndex = spaceToNodes[space][spaceToNodes[space].length - 1];
            spaceToNodes[space][indexInArray] = shiftedIndex;
            spaceOfNodes[shiftedIndex].indexInSpaceMap = indexInArray;
            spaceToNodes[space].length--;
        } else {
            spaceToNodes[space].length--;
        }
        delete spaceOfNodes[nodeIndex].freeSpace;
        delete spaceOfNodes[nodeIndex].indexInSpaceMap;
    }

    /**
     * @dev removeSpaceFromFractionalNode - occupies space from Fractional Node
     * function could be run only by SchainsFunctionality
     * @param nodeIndex - index of Node at array of Fractional Nodes
     * @param space - space which should be occupied
     */
    function removeSpaceFromNode(uint nodeIndex, uint8 space) external allow("SchainsFunctionalityInternal") returns (bool) {
        if (spaceOfNodes[nodeIndex].freeSpace < space) {
            return false;
        }
        if (space > 0) {
            moveNodeToNewSpaceMap(
                nodeIndex,
                spaceOfNodes[nodeIndex].freeSpace - space
            );
        }
        return true;
    }

    /**
     * @dev adSpaceToFractionalNode - returns space to Fractional Node
     * function could be run only be SchainsFunctionality
     * @param nodeIndex - index of Node at array of Fractional Nodes
     * @param space - space which should be returned
     */
    function addSpaceToNode(uint nodeIndex, uint8 space) external allow("SchainsFunctionality") {
        if (space > 0) {
            moveNodeToNewSpaceMap(
                nodeIndex,
                spaceOfNodes[nodeIndex].freeSpace + space
            );
        }
    }

    /**
     * @dev changeNodeLastRewardDate - changes Node's last reward date
     * function could be run only by SkaleManager
     * @param nodeIndex - index of Node
     */
    function changeNodeLastRewardDate(uint nodeIndex) external allow("SkaleManager") {
        nodes[nodeIndex].lastRewardDate = uint32(block.timestamp);
    }

    function changeNodeFinishTime(uint nodeIndex, uint32 time) external {
        nodes[nodeIndex].finishTime = time;
    }

    /**
     * @dev isNodeExist - checks existence of Node at this address
     * @param from - account address
     * @param nodeIndex - index of Node
     * @return if exist - true, else - false
     */
    function isNodeExist(address from, uint nodeIndex) external view returns (bool) {
        return nodeIndexes[from].isNodeExist[nodeIndex];
    }

    /**
     * @dev isTimeForReward - checks if time for reward has come
     * @param nodeIndex - index of Node
     * @return if time for reward has come - true, else - false
     */
    function isTimeForReward(uint nodeIndex) external view returns (bool) {
        address constantsAddress = contractManager.getContract("ConstantsHolder");
        return nodes[nodeIndex].lastRewardDate.add(IConstants(constantsAddress).rewardPeriod()) <= block.timestamp;
    }

    /**
     * @dev getNodeIP - get ip address of Node
     * @param nodeIndex - index of Node
     * @return ip address
     */
    function getNodeIP(uint nodeIndex) external view returns (bytes4) {
        return nodes[nodeIndex].ip;
    }

    /**
     * @dev getNodePort - get Node's port
     * @param nodeIndex - index of Node
     * @return port
     */
    function getNodePort(uint nodeIndex) external view returns (uint16) {
        return nodes[nodeIndex].port;
    }

    function getNodePublicKey(uint nodeIndex) external view returns (bytes memory) {
        return nodes[nodeIndex].publicKey;
    }

    function getNodeValidatorId(uint nodeIndex) external view returns (uint) {
        return nodes[nodeIndex].validatorId;
    }

    function getNodeFinishTime(uint nodeIndex) external view returns (uint32) {
        return nodes[nodeIndex].finishTime;
    }

    /**
     * @dev isNodeLeaving - checks if Node status Leaving
     * @param nodeIndex - index of Node
     * @return if Node status Leaving - true, else - false
     */
    function isNodeLeaving(uint nodeIndex) external view returns (bool) {
        return nodes[nodeIndex].status == NodeStatus.Leaving;
    }

    /**
     * @dev isNodeLeft - checks if Node status Left
     * @param nodeIndex - index of Node
     * @return if Node status Left - true, else - false
     */
    function isNodeLeft(uint nodeIndex) external view returns (bool) {
        return nodes[nodeIndex].status == NodeStatus.Left;
    }

    /**
     * @dev getNodeLastRewardDate - get Node last reward date
     * @param nodeIndex - index of Node
     * @return Node last reward date
     */
    function getNodeLastRewardDate(uint nodeIndex) external view returns (uint32) {
        return nodes[nodeIndex].lastRewardDate;
    }

    /**
     * @dev getNodeNextRewardDate - get Node next reward date
     * @param nodeIndex - index of Node
     * @return Node next reward date
     */
    function getNodeNextRewardDate(uint nodeIndex) external view returns (uint32) {
        address constantsAddress = contractManager.getContract("ConstantsHolder");
        return nodes[nodeIndex].lastRewardDate + IConstants(constantsAddress).rewardPeriod();
    }

    /**
     * @dev getNumberOfNodes - get number of Nodes
     * @return number of Nodes
     */
    function getNumberOfNodes() external view returns (uint) {
        return nodes.length;
    }

    /**
     * @dev getNumberOfFullNodes - get number Online Nodes
     * @return number of active nodes plus number of leaving nodes
     */
    function getNumberOnlineNodes() external view returns (uint) {
        return numberOfActiveNodes.add(numberOfLeavingNodes);
    }

    /**
     * @dev getActiveNodeIPs - get array of ips of Active Nodes
     * @return activeNodeIPs - array of ips of Active Nodes
     */
    function getActiveNodeIPs() external view returns (bytes4[] memory activeNodeIPs) {
        activeNodeIPs = new bytes4[](numberOfActiveNodes);
        uint indexOfActiveNodeIPs = 0;
        for (uint indexOfNodes = 0; indexOfNodes < nodes.length; indexOfNodes++) {
            if (isNodeActive(indexOfNodes)) {
                activeNodeIPs[indexOfActiveNodeIPs] = nodes[indexOfNodes].ip;
                indexOfActiveNodeIPs++;
            }
        }
    }

    /**
     * @dev getActiveNodesByAddress - get array of indexes of Active Nodes, which were
     * created by msg.sender
     * @return activeNodesbyAddress - array of indexes of Active Nodes, which were created
     * by msg.sender
     */
    function getActiveNodesByAddress() external view returns (uint[] memory activeNodesByAddress) {
        activeNodesByAddress = new uint[](nodeIndexes[msg.sender].numberOfNodes);
        uint indexOfActiveNodesByAddress = 0;
        for (uint indexOfNodes = 0; indexOfNodes < nodes.length; indexOfNodes++) {
            if (nodeIndexes[msg.sender].isNodeExist[indexOfNodes] && isNodeActive(indexOfNodes)) {
                activeNodesByAddress[indexOfActiveNodesByAddress] = indexOfNodes;
                indexOfActiveNodesByAddress++;
            }
        }
    }

    /**
     * @dev getActiveNodeIds - get array of indexes of Active Nodes
     * @return activeNodeIds - array of indexes of Active Nodes
     */
    function getActiveNodeIds() external view returns (uint[] memory activeNodeIds) {
        activeNodeIds = new uint[](numberOfActiveNodes);
        uint indexOfActiveNodeIds = 0;
        for (uint indexOfNodes = 0; indexOfNodes < nodes.length; indexOfNodes++) {
            if (isNodeActive(indexOfNodes)) {
                activeNodeIds[indexOfActiveNodeIds] = indexOfNodes;
                indexOfActiveNodeIds++;
            }
        }
    }

    function getValidatorId(uint nodeIndex) external view returns (uint) {
        require(nodeIndex < nodes.length, "Node does not exist");
        return nodes[nodeIndex].validatorId;
    }

    function getNodeStatus(uint nodeIndex) external view returns (NodeStatus) {
        return nodes[nodeIndex].status;
    }

    function initialize(address newContractsAddress) public initializer {
        Permissions.initialize(newContractsAddress);

        numberOfActiveNodes = 0;
        numberOfLeavingNodes = 0;
        numberOfLeftNodes = 0;
    }

    /**
     * @dev isNodeActive - checks if Node status Active
     * @param nodeIndex - index of Node
     * @return if Node status Active - true, else - false
     */
    function isNodeActive(uint nodeIndex) public view returns (bool) {
        return nodes[nodeIndex].status == NodeStatus.Active;
    }

    function moveNodeToNewSpaceMap(uint nodeIndex, uint8 newSpace) internal {
        uint8 previousSpace = spaceOfNodes[nodeIndex].freeSpace;
        uint indexInArray = spaceOfNodes[nodeIndex].indexInSpaceMap;
        if (indexInArray < spaceToNodes[previousSpace].length - 1) {
            uint shiftedIndex = spaceToNodes[previousSpace][spaceToNodes[previousSpace].length - 1];
            spaceToNodes[previousSpace][indexInArray] = shiftedIndex;
            spaceOfNodes[shiftedIndex].indexInSpaceMap = indexInArray;
            spaceToNodes[previousSpace].length--;
        } else {
            spaceToNodes[previousSpace].length--;
        }
        spaceToNodes[newSpace].push(nodeIndex);
        spaceOfNodes[nodeIndex].freeSpace = newSpace;
        spaceOfNodes[nodeIndex].indexInSpaceMap = spaceToNodes[newSpace].length - 1;
    }
}
