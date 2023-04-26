/**
 * Aave Protocol
 * Copyright (C) 2019 Aave
 * This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version.
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details
 */

pragma solidity 0.5.17;

/**
 * @title LendingPool contract
 * @notice Implements the actions of the LendingPool, and exposes accessory methods to fetch the users and reserve data
 * @author Aave
 */
contract LendingPool {
    /**
     * @dev deposits The underlying asset into the reserve. A corresponding amount of the overlying asset (aTokens)
     * is minted.
     * @param _reserve the address of the reserve
     * @param _amount the amount to be deposited
     * @param _referralCode integrators are assigned a referral code and can potentially receive rewards.
     */
    function deposit(address _reserve, uint256 _amount, uint16 _referralCode) external payable;
}
