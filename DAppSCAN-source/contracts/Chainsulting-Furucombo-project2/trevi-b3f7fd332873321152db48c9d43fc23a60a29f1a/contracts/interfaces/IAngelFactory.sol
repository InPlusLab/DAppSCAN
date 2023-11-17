// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IAngelFactory {
    // Getters
    function archangel() external view returns (address);
    function isValid(address angel) external view returns (bool);
    function rewardOf(address angel) external view returns (address);

    function create(address rewardToken) external returns (address);
}
