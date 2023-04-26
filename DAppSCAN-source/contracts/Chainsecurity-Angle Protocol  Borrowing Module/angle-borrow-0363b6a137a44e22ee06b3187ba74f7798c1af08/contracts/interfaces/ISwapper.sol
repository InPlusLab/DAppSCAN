// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ISwapper
/// @author Angle Core Team
/// @notice Interface for Swapper contracts
/// @dev This interface defines the key functions `Swapper` contracts should have when interacting with
/// Angle
interface ISwapper {
    /// @notice Notifies a contract that an address should be given `outToken` from `inToken`
    /// @param inToken Address of the token received
    /// @param outToken Address of the token to obtain
    /// @param outTokenRecipient Address to which the outToken should be sent
    /// @param outTokenOwed Minimum amount of outToken the `outTokenRecipient` address should have at the end of the call
    /// @param inTokenObtained Amount of collateral obtained by a related address prior
    /// to the call to this function
    /// @param data Extra data needed (to encode Uniswap swaps for instance)
    function swap(
        IERC20 inToken,
        IERC20 outToken,
        address outTokenRecipient,
        uint256 outTokenOwed,
        uint256 inTokenObtained,
        bytes calldata data
    ) external;
}
