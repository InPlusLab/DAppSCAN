pragma solidity ^0.5.4;

/// @title Opium.Interface.IOracleId contract is an interface that every oracleId should implement
interface IOracleId {
    /// @notice Requests data from `oracleId` one time
    /// @param timestamp uint256 Timestamp at which data are needed
    function fetchData(uint256 timestamp) external payable;

    /// @notice Requests data from `oracleId` multiple times
    /// @param timestamp uint256 Timestamp at which data are needed for the first time
    /// @param period uint256 Period in seconds between multiple timestamps
    /// @param times uint256 How many timestamps are requested
    function recursivelyFetchData(uint256 timestamp, uint256 period, uint256 times) external payable;

    /// @notice Requests and returns price in ETH for one request. This function could be called as `view` function. Oraclize API for price calculations restricts making this function as view.
    /// @return fetchPrice uint256 Price of one data request in ETH
    function calculateFetchPrice() external returns (uint256 fetchPrice);

    // Event with oracleId metadata JSON string (for DIB.ONE derivative explorer)
    event MetadataSet(string metadata);
}
