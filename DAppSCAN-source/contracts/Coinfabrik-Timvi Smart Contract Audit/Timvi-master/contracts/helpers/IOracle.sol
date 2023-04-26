pragma solidity 0.4.25;


/// @title IOracle
/// @dev Interface for getting the data from the oracle contract.
interface IOracle {
    function ethUsdPrice() external view returns(uint256);
}
