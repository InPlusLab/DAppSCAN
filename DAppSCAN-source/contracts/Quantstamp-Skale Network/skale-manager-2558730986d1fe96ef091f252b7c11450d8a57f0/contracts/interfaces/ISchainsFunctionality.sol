pragma solidity 0.5.16;

interface ISchainsFunctionality {
    function addSchain(address from, uint value, bytes calldata data) external;
    function deleteSchain(address from, string calldata name) external;
    function deleteSchainByRoot(string calldata name) external;
    function rotateNode(uint nodeIndex, bytes32 schainId) external returns (uint);
    function exitFromSchain(uint nodeIndex) external returns (bool);
}