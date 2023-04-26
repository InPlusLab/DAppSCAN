// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenRegistry {
    function owner() external view returns (address);
    function tokenFormulas(address) external view returns (address);
    function setTokenFormula(address token, address formula) external;
    function removeToken(address token) external;
    function changeOwner(address newOwner) external;
    event ChangedOwner(address indexed oldOwner, address indexed newOwner);
    event TokenAdded(address indexed token, address indexed formula);
    event TokenRemoved(address indexed token);
    event TokenFormulaUpdated(address indexed token, address indexed formula);
}