// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

interface IOracleIterator {
    /// @notice Proof of oracle iterator contract
    /// @dev Verifies that contract is a oracle iterator contract
    /// @return true if contract is a oracle iterator contract
    function isOracleIterator() external pure returns (bool);

    /// @notice Symbol of the oracle iterator
    /// @dev Should be resolved through OracleIteratorRegistry contract
    /// @return oracle iterator symbol
    function symbol() external pure returns (string memory);

    /// @notice Algorithm that, for the type of oracle used by the derivative,
    //  finds the value closest to a given timestamp
    /// @param _oracle iteratable oracle through
    /// @param _timestamp a given timestamp
    /// @param _roundHints specified rounds for a given timestamp
    /// @return the value closest to a given timestamp
    function getUnderlyingValue(
        address _oracle,
        uint256 _timestamp,
        uint256[] calldata _roundHints
    ) external view returns (int256);
}
