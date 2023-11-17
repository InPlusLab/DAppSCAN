pragma solidity 0.5.11;


/// @title IExchange
/// @dev Interface for interaction with the Exchange proposals logic contract to manage Exchange proposals.
interface IExchange {
    function create() external payable returns (uint256);
    function close(uint256 _id) external;
    function take(uint256 _id) external payable;
}
