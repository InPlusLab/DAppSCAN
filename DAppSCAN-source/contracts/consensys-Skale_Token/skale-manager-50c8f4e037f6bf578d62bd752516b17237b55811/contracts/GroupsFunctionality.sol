/*
    GroupsFunctionality.sol - SKALE Manager
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

import "./Permissions.sol";
import "./interfaces/IGroupsData.sol";


/**
 * @title SkaleVerifier - interface of SkaleVerifier
 */
interface ISkaleVerifier {
    function verify(
        uint sigx,
        uint sigy,
        uint hashx,
        uint hashy,
        uint pkx1,
        uint pky1,
        uint pkx2,
        uint pky2) external view returns (bool);
}


/**
 * @title GroupsFunctionality - contract with some Groups functionality, will be inherited by
 * MonitorsFunctionality and SchainsFunctionality
 */
contract GroupsFunctionality is Permissions {

    // informs that Group is added
    event GroupAdded(
        bytes32 groupIndex,
        bytes32 groupData,
        uint32 time,
        uint gasSpend
    );

    // informs that an exception set in Group
    event ExceptionSet(
        bytes32 groupIndex,
        uint exceptionNodeIndex,
        uint32 time,
        uint gasSpend
    );

    // informs that Group is deleted
    event GroupDeleted(
        bytes32 groupIndex,
        uint32 time,
        uint gasSpend
    );

    // informs that Group is upgraded
    event GroupUpgraded(
        bytes32 groupIndex,
        bytes32 groupData,
        uint32 time,
        uint gasSpend
    );

    // informs that Group is generated
    event GroupGenerated(
        bytes32 groupIndex,
        uint[] nodesInGroup,
        uint32 time,
        uint gasSpend
    );

    // name of executor contract
    string executorName;
    // name of data contract
    string dataName;

    /**
     * @dev contructor in Permissions approach
     * @param newExecutorName - name of executor contract
     * @param newDataName - name of data contract
     * @param newContractsAddress needed in Permissions constructor
     */
    constructor(string memory newExecutorName, string memory newDataName, address newContractsAddress) Permissions(newContractsAddress) public {
        executorName = newExecutorName;
        dataName = newDataName;
    }

    /**
     * @dev verifySignature - verify signature which create Group by Groups BLS master public key
     * @param groupIndex - Groups identifier
     * @param signatureX - first part of BLS signature
     * @param signatureY - second part of BLS signature
     * @param hashX - first part of hashed message
     * @param hashY - second part of hashed message
     * @return true - if correct, false - if not
     */
    function verifySignature(
        bytes32 groupIndex,
        uint signatureX,
        uint signatureY,
        uint hashX,
        uint hashY) external view returns (bool)
    {
        address groupsDataAddress = contractManager.contracts(keccak256(abi.encodePacked(dataName)));
        uint publicKeyx1;
        uint publicKeyy1;
        uint publicKeyx2;
        uint publicKeyy2;
        (publicKeyx1, publicKeyy1, publicKeyx2, publicKeyy2) = IGroupsData(groupsDataAddress).getGroupsPublicKey(groupIndex);
        address skaleVerifierAddress = contractManager.getContract("SkaleVerifier");
        return ISkaleVerifier(skaleVerifierAddress).verify(
            signatureX, signatureY, hashX, hashY, publicKeyx1, publicKeyy1, publicKeyx2, publicKeyy2
        );
    }

    /**
     * @dev addGroup - creates and adds new Group to Data contract
     * function could be run only by executor
     * @param groupIndex - Groups identifier
     * @param newRecommendedNumberOfNodes - recommended number of Nodes
     * @param data - some extra data
     */
    function addGroup(bytes32 groupIndex, uint newRecommendedNumberOfNodes, bytes32 data) public allow(executorName) {
        address groupsDataAddress = contractManager.contracts(keccak256(abi.encodePacked(dataName)));
        IGroupsData(groupsDataAddress).addGroup(groupIndex, newRecommendedNumberOfNodes, data);
        emit GroupAdded(
            groupIndex,
            data,
            uint32(block.timestamp),
            gasleft());
    }

    /**
     * @dev deleteGroup - delete Group from Data contract
     * function could be run only by executor
     * @param groupIndex - Groups identifier
     */
    function deleteGroup(bytes32 groupIndex) public allow(executorName) {
        address groupsDataAddress = contractManager.contracts(keccak256(abi.encodePacked(dataName)));
        require(IGroupsData(groupsDataAddress).isGroupActive(groupIndex), "Group is not active");
        IGroupsData(groupsDataAddress).removeGroup(groupIndex);
        IGroupsData(groupsDataAddress).removeAllNodesInGroup(groupIndex);
        emit GroupDeleted(groupIndex, uint32(block.timestamp), gasleft());
    }

    /**
     * @dev upgradeGroup - upgrade Group at Data contract
     * function could be run only by executor
     * @param groupIndex - Groups identifier
     * @param newRecommendedNumberOfNodes - recommended number of Nodes
     * @param data - some extra data
     */
    function upgradeGroup(bytes32 groupIndex, uint newRecommendedNumberOfNodes, bytes32 data) public allow(executorName) {
        address groupsDataAddress = contractManager.contracts(keccak256(abi.encodePacked(dataName)));
        require(IGroupsData(groupsDataAddress).isGroupActive(groupIndex), "Group is not active");
        IGroupsData(groupsDataAddress).removeGroup(groupIndex);
        IGroupsData(groupsDataAddress).removeAllNodesInGroup(groupIndex);
        IGroupsData(groupsDataAddress).addGroup(groupIndex, newRecommendedNumberOfNodes, data);
        emit GroupUpgraded(
            groupIndex,
            data,
            uint32(block.timestamp),
            gasleft());
    }

    /**
     * @dev findNode - find local index of Node in Schain
     * @param groupIndex - Groups identifier
     * @param nodeIndex - global index of Node
     * @return local index of Node in Schain
     */
    function findNode(bytes32 groupIndex, uint nodeIndex) internal view returns (uint index) {
        address groupsDataAddress = contractManager.contracts(keccak256(abi.encodePacked(dataName)));
        uint[] memory nodesInGroup = IGroupsData(groupsDataAddress).getNodesInGroup(groupIndex);
        for (index = 0; index < nodesInGroup.length; index++) {
            if (nodesInGroup[index] == nodeIndex) {
                return index;
            }
        }
        return index;
    }

    /**
     * @dev generateGroup - abstract method which would be implemented in inherited contracts
     * function generates group of Nodes
     * @param groupIndex - Groups identifier
     * return array of indexes of Nodes in Group
     */
    function generateGroup(bytes32 groupIndex) internal returns (uint[] memory);
    function selectNodeToGroup(bytes32 groupIndex) internal returns (uint);

    function swap(uint[] memory array, uint index1, uint index2) internal pure {
        uint buffer = array[index1];
        array[index1] = array[index2];
        array[index2] = buffer;
    }
}
