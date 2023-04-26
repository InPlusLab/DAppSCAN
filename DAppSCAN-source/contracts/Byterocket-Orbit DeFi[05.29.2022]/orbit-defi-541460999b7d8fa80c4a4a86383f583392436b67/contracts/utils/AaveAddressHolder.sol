// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import '../../interfaces/IAaveAddressHolder.sol';

contract AaveAddressHolder is IAaveAddressHolder {
    address public override lendingPoolAddress;

    constructor(address _lendingPoolAddress) {
        lendingPoolAddress = _lendingPoolAddress;
    }

    ///@notice Set the address of the lending pool from aave
    ///@param newAddress The address of the lending pool from aave
    function setLendingPoolAddress(address newAddress) external override {
        lendingPoolAddress = newAddress;
    }
}
