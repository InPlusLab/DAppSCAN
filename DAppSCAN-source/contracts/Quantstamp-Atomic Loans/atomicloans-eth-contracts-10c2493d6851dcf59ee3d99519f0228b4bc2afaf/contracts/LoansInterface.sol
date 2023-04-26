pragma solidity ^0.5.10;

interface LoansInterface {
    function secretHashes(bytes32) external view returns (bytes32, bytes32, bytes32, bytes32, bytes32, bool);
    function pubKeys(bytes32) external view returns (bytes memory, bytes memory, bytes memory);
    function liquidationExpiration(bytes32) external view returns (uint256);
    function seizureExpiration(bytes32) external view returns (uint256);
}
