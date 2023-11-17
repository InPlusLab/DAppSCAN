// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IFountainFactory {
    // Getter
    function archangel() external view returns (address);
    function isValid(address fountain) external view returns (bool);
    function fountainOf(address token) external view returns (address);

    function create(address token) external returns (address);
}
