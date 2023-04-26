/*
    SchainsFunctionalityInternal.sol - SKALE Manager
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

import "./GroupsFunctionality.sol";
import "./interfaces/INodesData.sol";
import "./interfaces/IConstants.sol";
import "./SchainsData.sol";


/**
 * @title SchainsFunctionality - contract contains all functionality logic to manage Schains
 */
contract SchainsFunctionalityInternal is GroupsFunctionality {
    // informs that Schain based on some Nodes
    event SchainNodes(
        string name,
        bytes32 groupIndex,
        uint[] nodesInGroup,
        uint32 time,
        uint gasSpend
    );

    /**
     * @dev createGroupForSchain - creates Group for Schain
     * @param schainName - name of Schain
     * @param schainId - hash by name of Schain
     * @param numberOfNodes - number of Nodes needed for this Schain
     * @param partOfNode - divisor of given type of Schain
     */
    function createGroupForSchain(
        string calldata schainName,
        bytes32 schainId,
        uint numberOfNodes,
        uint8 partOfNode) external allow(executorName)
    {
        address dataAddress = contractManager.getContract(dataName);
        addGroup(schainId, numberOfNodes, bytes32(uint(partOfNode)));
        uint[] memory numberOfNodesInGroup = generateGroup(schainId);
        SchainsData(dataAddress).setSchainPartOfNode(schainId, partOfNode);
        emit SchainNodes(
            schainName,
            schainId,
            numberOfNodesInGroup,
            uint32(block.timestamp),
            gasleft());
    }

    /**
     * @dev getNodesDataFromTypeOfSchain - returns number if Nodes
     * and part of Node which needed to this Schain
     * @param typeOfSchain - type of Schain
     * @return numberOfNodes - number of Nodes needed to this Schain
     * @return partOfNode - divisor of given type of Schain
     */
    function getNodesDataFromTypeOfSchain(uint typeOfSchain) external view returns (uint numberOfNodes, uint8 partOfNode) {
        address constantsAddress = contractManager.getContract("ConstantsHolder");
        numberOfNodes = IConstants(constantsAddress).NUMBER_OF_NODES_FOR_SCHAIN();
        if (typeOfSchain == 1) {
            partOfNode = IConstants(constantsAddress).TINY_DIVISOR() / IConstants(constantsAddress).TINY_DIVISOR();
        } else if (typeOfSchain == 2) {
            partOfNode = IConstants(constantsAddress).TINY_DIVISOR() / IConstants(constantsAddress).SMALL_DIVISOR();
        } else if (typeOfSchain == 3) {
            partOfNode = IConstants(constantsAddress).TINY_DIVISOR() / IConstants(constantsAddress).MEDIUM_DIVISOR();
        } else if (typeOfSchain == 4) {
            partOfNode = 0;
            numberOfNodes = IConstants(constantsAddress).NUMBER_OF_NODES_FOR_TEST_SCHAIN();
        } else if (typeOfSchain == 5) {
            partOfNode = IConstants(constantsAddress).TINY_DIVISOR() / IConstants(constantsAddress).MEDIUM_TEST_DIVISOR();
            numberOfNodes = IConstants(constantsAddress).NUMBER_OF_NODES_FOR_MEDIUM_TEST_SCHAIN();
        } else {
            revert("Bad schain type");
        }
    }

    function removeNodeFromSchain(uint nodeIndex, bytes32 groupHash) external allowTwo(executorName, "SkaleDKG") {
        address schainsDataAddress = contractManager.contracts(keccak256(abi.encodePacked("SchainsData")));
        uint groupIndex = findSchainAtSchainsForNode(nodeIndex, groupHash);
        uint indexOfNode = findNode(groupHash, nodeIndex);
        IGroupsData(schainsDataAddress).removeNodeFromGroup(indexOfNode, groupHash);
        // IGroupsData(schainsDataAddress).removeExceptionNode(groupHash, nodeIndex);
        SchainsData(schainsDataAddress).removeSchainForNode(nodeIndex, groupIndex);
    }

    function removeNodeFromExceptions(bytes32 groupHash, uint nodeIndex) external allow(executorName) {
        address schainsDataAddress = contractManager.contracts(keccak256(abi.encodePacked("SchainsData")));
        IGroupsData(schainsDataAddress).removeExceptionNode(groupHash, nodeIndex);
    }

    function isEnoughNodes(bytes32 groupIndex) external view returns (uint[] memory result) {
        IGroupsData groupsData = IGroupsData(contractManager.getContract(dataName));
        INodesData nodesData = INodesData(contractManager.getContract("NodesData"));
        uint8 space = uint8(uint(groupsData.getGroupData(groupIndex)));
        uint[] memory nodesWithFreeSpace = nodesData.getNodesWithFreeSpace(space);
        uint counter = 0;
        for (uint i = 0; i < nodesWithFreeSpace.length; i++) {
            if (!isCorrespond(groupIndex, nodesWithFreeSpace[i])) {
                counter++;
            }
        }
        if (counter < nodesWithFreeSpace.length) {
            result = new uint[](nodesWithFreeSpace.length.sub(counter));
            counter = 0;
            for (uint i = 0; i < nodesWithFreeSpace.length; i++) {
                if (isCorrespond(groupIndex, nodesWithFreeSpace[i])) {
                    result[counter] = nodesWithFreeSpace[i];
                    counter++;
                }
            }
        }
    }

    function isAnyFreeNode(bytes32 groupIndex) external view returns (bool) {
        IGroupsData groupsData = IGroupsData(contractManager.getContract(dataName));
        INodesData nodesData = INodesData(contractManager.getContract("NodesData"));
        uint8 space = uint8(uint(groupsData.getGroupData(groupIndex)));
        uint[] memory nodesWithFreeSpace = nodesData.getNodesWithFreeSpace(space);
        for (uint i = 0; i < nodesWithFreeSpace.length; i++) {
            if (isCorrespond(groupIndex, nodesWithFreeSpace[i])) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev selectNodeToGroup - pseudo-randomly select new Node for Schain
     * @param groupIndex - hash of name of Schain
     * @return nodeIndex - global index of Node
     */
    function selectNodeToGroup(bytes32 groupIndex) external allow(executorName) returns (uint) {
        IGroupsData groupsData = IGroupsData(contractManager.getContract(dataName));
        SchainsData schainsData = SchainsData(contractManager.getContract(dataName));
        require(groupsData.isGroupActive(groupIndex), "Group is not active");
        uint8 space = uint8(uint(groupsData.getGroupData(groupIndex)));
        uint[] memory possibleNodes = this.isEnoughNodes(groupIndex);
        require(possibleNodes.length > 0, "No any free Nodes for rotation");
        uint nodeIndex;
        uint random = uint(keccak256(abi.encodePacked(uint(blockhash(block.number - 1)), groupIndex)));
        do {
            uint index = random % possibleNodes.length;
            nodeIndex = possibleNodes[index];
            random = uint(keccak256(abi.encodePacked(random, nodeIndex)));
        } while (groupsData.isExceptionNode(groupIndex, nodeIndex));
        require(removeSpace(nodeIndex, space), "Could not remove space from nodeIndex");
        schainsData.addSchainForNode(nodeIndex, groupIndex);
        groupsData.setException(groupIndex, nodeIndex);
        groupsData.setNodeInGroup(groupIndex, nodeIndex);
        return nodeIndex;
    }

    function initialize(address newContractsAddress) public initializer {
        GroupsFunctionality.initialize("SchainsFunctionality", "SchainsData", newContractsAddress);
    }

    /**
     * @dev findSchainAtSchainsForNode - finds index of Schain at schainsForNode array
     * @param nodeIndex - index of Node at common array of Nodes
     * @param schainId - hash of name of Schain
     * @return index of Schain at schainsForNode array
     */
    function findSchainAtSchainsForNode(uint nodeIndex, bytes32 schainId) public view returns (uint) {
        address dataAddress = contractManager.contracts(keccak256(abi.encodePacked(dataName)));
        uint length = SchainsData(dataAddress).getLengthOfSchainsForNode(nodeIndex);
        for (uint i = 0; i < length; i++) {
            if (SchainsData(dataAddress).schainsForNodes(nodeIndex, i) == schainId) {
                return i;
            }
        }
        return length;
    }

    /**
     * @dev generateGroup - generates Group for Schain
     * @param groupIndex - index of Group
     */
    function generateGroup(bytes32 groupIndex) internal returns (uint[] memory nodesInGroup) {
        IGroupsData groupsData = IGroupsData(contractManager.getContract(dataName));
        SchainsData schainsData = SchainsData(contractManager.getContract(dataName));
        require(groupsData.isGroupActive(groupIndex), "Group is not active");

        // uint numberOfNodes = setNumberOfNodesInGroup(groupIndex, uint(groupsData.getGroupData(groupIndex)), address(groupsData));
        uint8 space = uint8(uint(groupsData.getGroupData(groupIndex)));
        // (numberOfNodes, space) = setNumberOfNodesInGroup(groupIndex, uint(groupsData.getGroupData(groupIndex)), address(groupsData));

        nodesInGroup = new uint[](groupsData.getRecommendedNumberOfNodes(groupIndex));

        uint[] memory possibleNodes = this.isEnoughNodes(groupIndex);
        require(possibleNodes.length >= nodesInGroup.length, "Not enough nodes to create Schain");
        uint ignoringTail = 0;
        uint random = uint(keccak256(abi.encodePacked(uint(blockhash(block.number - 1)), groupIndex)));
        for (uint i = 0; i < nodesInGroup.length; ++i) {
            uint index = random % (possibleNodes.length.sub(ignoringTail));
            uint node = possibleNodes[index];
            nodesInGroup[i] = node;
            swap(possibleNodes, index, possibleNodes.length.sub(ignoringTail) - 1);
            ++ignoringTail;

            groupsData.setException(groupIndex, node);
            schainsData.addSchainForNode(node, groupIndex);
            require(removeSpace(node, space), "Could not remove space from Node");
        }

        // set generated group
        groupsData.setNodesInGroup(groupIndex, nodesInGroup);
        emit GroupGenerated(
            groupIndex,
            nodesInGroup,
            uint32(block.timestamp),
            gasleft());
    }

    /**
     * @dev removeSpace - occupy space of given Node
     * @param nodeIndex - index of Node at common array of Nodes
     * @param space - needed space to occupy
     * @return if ouccupied - true, else - false
     */
    function removeSpace(uint nodeIndex, uint8 space) internal returns (bool) {
        address nodesDataAddress = contractManager.getContract("NodesData");
        return INodesData(nodesDataAddress).removeSpaceFromNode(nodeIndex, space);
    }

    function isCorrespond(bytes32 groupIndex, uint nodeIndex) internal view returns (bool) {
        IGroupsData groupsData = IGroupsData(contractManager.contracts(keccak256(abi.encodePacked(dataName))));
        INodesData nodesData = INodesData(contractManager.contracts(keccak256(abi.encodePacked("NodesData"))));
        return !groupsData.isExceptionNode(groupIndex, nodeIndex) && nodesData.isNodeActive(nodeIndex);
    }
}
