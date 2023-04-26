// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

/**
 * @title The Depositary Oracle interface.
 */
interface IDepositaryOracle {
    /// @notice Type of security on depositary.
    struct Security {
        // International securities identification number.
        string isin;
        // Amount.
        uint256 amount;
    }

    /**
     * @notice Write a security amount to the storage mapping.
     * @param isin International securities identification number.
     * @param amount Amount of securities.
     */
    function put(string calldata isin, uint256 amount) external;

    /**
     * @notice Get amount securities.
     * @param isin International securities identification number.
     * @return amount Amount of securities.
     */
    function get(string calldata isin) external view returns (Security memory);

    /**
     * @notice Get all depositary securities.
     * @return All securities.
     */
    function all() external view returns (Security[] memory);

    /**
     * @dev Emitted when the depositary update.
     */
    event Update(string isin, uint256 amount);
}
