pragma solidity ^0.5.3;

/**
 * @title GroupsData - interface of GroupsData
 */
interface IGroupsData {
    function addGroup(bytes32 groupIndex, uint amountOfNodes, bytes32 data) external;
    function removeAllNodesInGroup(bytes32 groupIndex) external;
    // function setNewAmountOfNodes(bytes32 groupIndex, uint amountOfNodes) external;
    // function setNewGroupData(bytes32 groupIndex, bytes32 data) external;
    function setNodeInGroup(bytes32 groupIndex, uint nodeIndex) external;
    function setNodesInGroup(bytes32 groupIndex, uint[] calldata nodesInGroup) external;
    function removeExceptionNode(bytes32 groupIndex, uint nodeIndex) external;
    function removeGroup(bytes32 groupIndex) external;
    function setException(bytes32 groupIndex, uint nodeIndex) external;
    function isGroupActive(bytes32 groupIndex) external view returns (bool);
    function isExceptionNode(bytes32 groupIndex, uint nodeIndex) external view returns (bool);
    function getGroupsPublicKey(bytes32 groupIndex) external view returns (uint, uint, uint, uint);
    function getNodesInGroup(bytes32 schainId) external view returns (uint[] memory);
    function getGroupData(bytes32 groupIndex) external view returns (bytes32);
    function getRecommendedNumberOfNodes(bytes32 groupIndex) external view returns (uint);
    function getNumberOfNodesInGroup(bytes32 groupIndex) external view returns (uint);
    function isGroupFailedDKG(bytes32 groupIndex) external view returns (bool);
    function removeNodeFromGroup(uint nodeIndex, bytes32 groupIndex) external;
    function setPublicKey(
        bytes32 groupIndex,
        uint pubKeyx1,
        uint pubKeyy1,
        uint pubKeyx2,
        uint pubKeyy2) external;
    function setGroupFailedDKG(bytes32 groupIndex) external;
}