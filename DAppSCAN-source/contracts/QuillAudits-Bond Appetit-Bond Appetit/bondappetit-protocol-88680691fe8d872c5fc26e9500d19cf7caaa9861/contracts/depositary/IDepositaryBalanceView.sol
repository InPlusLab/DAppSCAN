// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

/**
 * @title The Depositary Balance interface.
 */
interface IDepositaryBalanceView {
    /**
     * @notice Get decimals balance.
     * @return Decimals balance.
     */
    function decimals() external view returns(uint256);

    /**
     * @notice Get balance of depositary.
     * @return Balance of depositary.
     */
    function balance() external view returns(uint256);
}