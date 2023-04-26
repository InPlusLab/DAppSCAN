/*
    GroupsData.sol - SKALE Manager
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
pragma experimental ABIEncoderV2;

import "./Permissions.sol";
import "./interfaces/IGroupsData.sol";


interface ISkaleDKG {
    function openChannel(bytes32 groupIndex) external;
    function deleteChannel(bytes32 groupIndex) external;
    function isChannelOpened(bytes32 groupIndex) external view returns (bool);
}


/**
 * @title GroupsData - contract with some Groups data, will be inherited by
 * SchainsData and ValidatorsData.
 */
contract GroupsData is IGroupsData, Permissions {

    // struct to note which Node has already joined to the group
    struct GroupCheck {
        mapping (uint => bool) check;
    }

    struct Group {
        bool active;
        bytes32 groupData;
        uint[] nodesInGroup;
        uint recommendedNumberOfNodes;
        // BLS master public key
        uint[4] groupsPublicKey;
        bool succesfulDKG;
    }

    // contain all groups
    mapping (bytes32 => Group) public groups;
    // past groups common BLS public keys
    mapping (bytes32 => uint[4][]) public previousPublicKeys;
    // mapping for checking Has Node already joined to the group
    mapping (bytes32 => GroupCheck) exceptions;

    // name of executor contract
    string executorName;

    /**
     * @dev addGroup - creates and adds new Group to mapping
     * function could be run only by executor
     * @param groupIndex - Groups identifier
     * @param amountOfNodes - recommended number of Nodes in this Group
     * @param data - some extra data
     */
    function addGroup(bytes32 groupIndex, uint amountOfNodes, bytes32 data) external allow(executorName) {
        groups[groupIndex].active = true;
        groups[groupIndex].recommendedNumberOfNodes = amountOfNodes;
        groups[groupIndex].groupData = data;
        // Open channel in SkaleDKG
        address skaleDKGAddress = contractManager.getContract("SkaleDKG");
        ISkaleDKG(skaleDKGAddress).openChannel(groupIndex);
    }

    /**
     * @dev setException - sets a Node like exception
     * function could be run only by executor
     * @param groupIndex - Groups identifier
     * @param nodeIndex - index of Node which would be notes like exception
     */
    function setException(bytes32 groupIndex, uint nodeIndex) external allow(executorName) {
        exceptions[groupIndex].check[nodeIndex] = true;
    }

    /**
     * @dev setPublicKey - sets BLS master public key
     * function could be run only by SkaleDKG
     * @param groupIndex - Groups identifier
     * @param publicKeyx1 }
     * @param publicKeyy1 } parts of BLS master public key
     * @param publicKeyx2 }
     * @param publicKeyy2 }
     */
    function setPublicKey(
        bytes32 groupIndex,
        uint publicKeyx1,
        uint publicKeyy1,
        uint publicKeyx2,
        uint publicKeyy2) external allow("SkaleDKG")
    {
        if (!isPublicKeyZero(groupIndex)) {
            uint[4] memory previousKey = groups[groupIndex].groupsPublicKey;
            previousPublicKeys[groupIndex].push(previousKey);
        }
        groups[groupIndex].groupsPublicKey[0] = publicKeyx1;
        groups[groupIndex].groupsPublicKey[1] = publicKeyy1;
        groups[groupIndex].groupsPublicKey[2] = publicKeyx2;
        groups[groupIndex].groupsPublicKey[3] = publicKeyy2;
    }

    /**
     * @dev setNodeInGroup - adds Node to Group
     * function could be run only by executor
     * @param groupIndex - Groups identifier
     * @param nodeIndex - index of Node which would be added to the Group
     */
    function setNodeInGroup(bytes32 groupIndex, uint nodeIndex) external allow(executorName) {
        groups[groupIndex].nodesInGroup.push(nodeIndex);
    }

    /**
     * @dev removeNodeFromGroup - removes Node out of the Group
     * function could be run only by executor
     * @param indexOfNode - Nodes identifier
     * @param groupIndex - Groups identifier
     */
    function removeNodeFromGroup(uint indexOfNode, bytes32 groupIndex) external allow(executorName) {
        uint size = groups[groupIndex].nodesInGroup.length;
        if (indexOfNode < size) {
            groups[groupIndex].nodesInGroup[indexOfNode] = groups[groupIndex].nodesInGroup[size - 1];
        }
        delete groups[groupIndex].nodesInGroup[size - 1];
        groups[groupIndex].nodesInGroup.length--;
    }

    /**
     * @dev removeAllNodesInGroup - removes all added Nodes out the Group
     * function could be run only by executor
     * @param groupIndex - Groups identifier
     */
    function removeAllNodesInGroup(bytes32 groupIndex) external allow(executorName) {
        delete groups[groupIndex].nodesInGroup;
        groups[groupIndex].nodesInGroup.length = 0;
    }

    /**
     * @dev setNodesInGroup - adds Nodes to Group
     * function could be run only by executor
     * @param groupIndex - Groups identifier
     * @param nodesInGroup - array of indexes of Nodes which would be added to the Group
    */
    function setNodesInGroup(bytes32 groupIndex, uint[] calldata nodesInGroup) external allow(executorName) {
        groups[groupIndex].nodesInGroup = nodesInGroup;
    }

    function setGroupFailedDKG(bytes32 groupIndex) external allow("SkaleDKG") {
        groups[groupIndex].succesfulDKG = false;
    }

    /**
     * @dev removeGroup - remove Group from storage
     * function could be run only be executor
     * @param groupIndex - Groups identifier
     */
    function removeGroup(bytes32 groupIndex) external allow(executorName) {
        groups[groupIndex].active = false;
        delete groups[groupIndex].groupData;
        delete groups[groupIndex].recommendedNumberOfNodes;
        uint[4] memory previousKey = groups[groupIndex].groupsPublicKey;
        previousPublicKeys[groupIndex].push(previousKey);
        delete groups[groupIndex].groupsPublicKey;
        delete groups[groupIndex];
        // delete channel
        address skaleDKGAddress = contractManager.getContract("SkaleDKG");

        if (ISkaleDKG(skaleDKGAddress).isChannelOpened(groupIndex)) {
            ISkaleDKG(skaleDKGAddress).deleteChannel(groupIndex);
        }
    }

    /**
     * @dev removeExceptionNode - remove exception Node from Group
     * function could be run only by executor
     * @param groupIndex - Groups identifier
     */
    function removeExceptionNode(bytes32 groupIndex, uint nodeIndex) external allow(executorName) {
        exceptions[groupIndex].check[nodeIndex] = false;
    }

    /**
     * @dev isGroupActive - checks is Group active
     * @param groupIndex - Groups identifier
     * @return true - active, false - not active
     */
    function isGroupActive(bytes32 groupIndex) external view returns (bool) {
        return groups[groupIndex].active;
    }

    /**
     * @dev isExceptionNode - checks is Node - exception at given Group
     * @param groupIndex - Groups identifier
     * @param nodeIndex - index of Node
     * return true - exception, false - not exception
     */
    function isExceptionNode(bytes32 groupIndex, uint nodeIndex) external view returns (bool) {
        return exceptions[groupIndex].check[nodeIndex];
    }

    /**
     * @dev getGroupsPublicKey - shows Groups public key
     * @param groupIndex - Groups identifier
     * @return publicKey(x1, y1, x2, y2) - parts of BLS master public key
     */
    function getGroupsPublicKey(bytes32 groupIndex) external view returns (uint, uint, uint, uint) {
        return (
            groups[groupIndex].groupsPublicKey[0],
            groups[groupIndex].groupsPublicKey[1],
            groups[groupIndex].groupsPublicKey[2],
            groups[groupIndex].groupsPublicKey[3]
        );
    }

    function getPreviousGroupsPublicKey(bytes32 groupIndex) external view returns (uint, uint, uint, uint) {
        uint length = previousPublicKeys[groupIndex].length;
        if (length == 0) {
            return (0, 0, 0, 0);
        }
        return (
            previousPublicKeys[groupIndex][length - 1][0],
            previousPublicKeys[groupIndex][length - 1][1],
            previousPublicKeys[groupIndex][length - 1][2],
            previousPublicKeys[groupIndex][length - 1][3]
        );
    }

    function isGroupFailedDKG(bytes32 groupIndex) external view returns (bool) {
        return !groups[groupIndex].succesfulDKG;
    }

    /**
     * @dev getNodesInGroup - shows Nodes in Group
     * @param groupIndex - Groups identifier
     * @return array of indexes of Nodes in Group
     */
    function getNodesInGroup(bytes32 groupIndex) external view returns (uint[] memory) {
        return groups[groupIndex].nodesInGroup;
    }

    /**
     * @dev getGroupsData - shows Groups extra data
     * @param groupIndex - Groups identifier
     * @return Groups extra data
     */
    function getGroupData(bytes32 groupIndex) external view returns (bytes32) {
        return groups[groupIndex].groupData;
    }

    /**
     * @dev getRecommendedNumberOfNodes - shows recommended number of Nodes
     * @param groupIndex - Groups identifier
     * @return recommended number of Nodes
     */
    function getRecommendedNumberOfNodes(bytes32 groupIndex) external view returns (uint) {
        return groups[groupIndex].recommendedNumberOfNodes;
    }

    /**
     * @dev getNumberOfNodesInGroup - shows number of Nodes in Group
     * @param groupIndex - Groups identifier
     * @return number of Nodes in Group
     */
    function getNumberOfNodesInGroup(bytes32 groupIndex) external view returns (uint) {
        return groups[groupIndex].nodesInGroup.length;
    }

    /**
     * @dev constructor in Permissions approach
     * @param newExecutorName - name of executor contract
     * @param newContractsAddress needed in Permissions constructor
     */
    function initialize(string memory newExecutorName, address newContractsAddress) public initializer {
        Permissions.initialize(newContractsAddress);
        executorName = newExecutorName;
    }

    function isPublicKeyZero(bytes32 groupIndex) internal view returns (bool) {
        return groups[groupIndex].groupsPublicKey[0] == 0 &&
            groups[groupIndex].groupsPublicKey[1] == 0 &&
            groups[groupIndex].groupsPublicKey[2] == 0 &&
            groups[groupIndex].groupsPublicKey[3] == 0;
    }

}
