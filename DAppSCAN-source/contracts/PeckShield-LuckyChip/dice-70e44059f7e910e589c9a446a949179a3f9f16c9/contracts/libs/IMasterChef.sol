// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IMasterChef {
    /**
     * @dev Update bonus.
     */
    function updateBonus(uint256 _pid) external;
}
