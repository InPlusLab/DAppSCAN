// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IPool.sol";


interface IDefaultPool is IPool {
    // --- Events ---
    event VaultManagerAddressChanged(address _newVaultManagerAddress);
    event COLTokenAddressChanged(address _newCOLTokenAddress);
    event DefaultPoolBAIDebtUpdated(uint _BAIDebt);
    event DefaultPoolCOLBalanceUpdated(uint _COL);

    // --- Functions ---
    function sendCOLToActivePool(uint _amount) external;
}
