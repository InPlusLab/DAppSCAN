// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICurve {
    function fixedY() external view returns (uint256);

    function minX() external view returns (uint256);

    function maxX() external view returns (uint256);

    function minY() external view returns (uint256);

    function maxY() external view returns (uint256);

    function getY(uint256 x) external view returns (uint256);
}
