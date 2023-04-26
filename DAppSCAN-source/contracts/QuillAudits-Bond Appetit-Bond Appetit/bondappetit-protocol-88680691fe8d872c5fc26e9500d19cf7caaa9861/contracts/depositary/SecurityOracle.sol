// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ISecurityOracle.sol";

contract SecurityOracle is ISecurityOracle, Ownable {
    /// @dev Data of security properties.
    mapping(string => mapping(string => bytes)) private data;

    function put(
        string calldata isin,
        string calldata prop,
        bytes calldata value
    ) external override onlyOwner {
        data[isin][prop] = value;
        emit Update(isin, prop, value);
    }

    function get(string calldata isin, string calldata prop) external override view returns (bytes memory) {
        return data[isin][prop];
    }
}
