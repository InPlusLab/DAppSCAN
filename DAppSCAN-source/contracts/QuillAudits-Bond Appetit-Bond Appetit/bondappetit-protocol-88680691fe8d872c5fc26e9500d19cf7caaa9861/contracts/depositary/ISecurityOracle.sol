// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

/**
 * @title The Security Oracle interface.
 */
interface ISecurityOracle {
    /**
     * @notice Put property value of security.
     * @param isin International securities identification number of security.
     * @param prop Property name of security.
     * @param value Property value.
     */
    function put(string calldata isin, string calldata prop, bytes calldata value) external;

    /**
     * @notice Get property value of security.
     * @param isin International securities identification number of security.
     * @param prop Property name of security.
     * @return Property value of security.
     */
    function get(string calldata isin, string calldata prop) external view returns(bytes memory);

    /**
     * @dev Emitted when the security property update.
     */
    event Update(string isin, string prop, bytes value);
}
