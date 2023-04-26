pragma solidity ^0.5.3;

interface ITokenSaleManager {

    /// @notice Allocates values for `walletAddresses`
    function approve(address[] calldata walletAddress, uint[] calldata value) external;

    /// @notice Transfers the entire value to sender address. Tokens are locked.
    function retrieve() external;

    /// @notice Allows seller address to approve tokens transfers
    function registerSeller(address seller) external;
}