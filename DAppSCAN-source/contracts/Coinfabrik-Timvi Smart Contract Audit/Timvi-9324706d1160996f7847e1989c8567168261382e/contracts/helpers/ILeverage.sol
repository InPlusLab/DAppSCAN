pragma solidity 0.5.11;


/// @title ILeverage
/// @dev Interface for interaction with the Leverage proposals logic contract to manage Leverage proposals.
interface ILeverage {
    function create(uint256 _percent) external payable returns (uint256);
    function close(uint256 _id) external;
    function take(uint256 _id) external payable;
}
