// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.6;

/// @author Ganesh Gautham Elango
/// @title SNX Flash Loan Tool interface
interface ISNXFlashLoanTool {
    /// @notice Emitted on each burn
    /// @param sender msg.sender
    /// @param sUSDAmount Amount of sUSD debt burnt
    /// @param snxAmount Amount of SNX to sell in order to burn sUSD debt
    event Burn(address sender, uint256 sUSDAmount, uint256 snxAmount);

    /// @notice Burn sUSD debt with SNX using a flash loan
    /// @dev To burn all sUSD debt, pass in type(uint256).max for sUSDAmount
    /// @param sUSDAmount Amount of sUSD debt to burn (set to type(uint256).max to burn all debt)
    /// @param snxAmount Amount of SNX to sell in order to burn sUSD debt
    /// @param exchange Exchange address to swap on
    /// @param exchangeData Calldata to call exchange with
    function burn(
        uint256 sUSDAmount,
        uint256 snxAmount,
        address exchange,
        bytes calldata exchangeData
    ) external;
}
