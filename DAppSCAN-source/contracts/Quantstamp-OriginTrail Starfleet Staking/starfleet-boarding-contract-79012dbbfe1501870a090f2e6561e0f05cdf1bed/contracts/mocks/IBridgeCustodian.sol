pragma solidity ^0.6.10;

/// @title IBridgeCustodian interface - The interface required for an address to qualify as a custodian.
interface IBridgeCustodian {
    function getOwners() external view returns (address[] memory);
}
