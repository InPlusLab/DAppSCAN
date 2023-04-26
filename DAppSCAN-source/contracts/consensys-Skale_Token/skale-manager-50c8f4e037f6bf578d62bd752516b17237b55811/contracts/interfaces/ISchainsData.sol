pragma solidity ^0.5.3;


/**
 * @title SchainsData - interface of SchainsData contract
 * Contains only needed functions for current contract
 */
interface ISchainsData {
    function schainsAtSystem(uint index) external view returns (bytes32);
    function numberOfSchains() external view returns (uint64);
    function sumOfSchainsResources() external view returns (uint);
    function addSchainForNode(uint nodeIndex, bytes32 schainId) external;
    function setSchainPartOfNode(bytes32 schainId, uint8 partOfNode) external;
    function getLengthOfSchainsForNode(uint nodeIndex) external view returns (uint);
    function schainsForNodes(uint nodeIndex, uint indexOfSchain) external view returns (bytes32);
    function getSchainOwner(bytes32 schainId) external view returns (address);
    function initializeSchain(
        string calldata name,
        address from,
        uint lifetime,
        uint deposit) external;
    function setSchainIndex(bytes32 schainId, address from) external;
    function removeSchain(bytes32 schainId, address from) external;
    function removeSchainForNode(uint nodeIndex, uint schainIndex) external;
    function isTimeExpired(bytes32 schainId) external view returns (bool);
    function isOwnerAddress(address from, bytes32 schainId) external view returns (bool);
    function isSchainNameAvailable(string calldata name) external view returns (bool);
    function getSchainsPartOfNode(bytes32 schainId) external view returns (uint8);
    function getSchainIdsForNode(uint nodeIndex) external view returns (bytes32[] memory);
}
