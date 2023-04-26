// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IPool.sol";
import "./ICollSurplusPool.sol";
import "./IDefaultPool.sol";
import "./IStabilityPool.sol";


interface IActivePool is IPool {
    // --- Events ---
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event VaultManagerAddressChanged(address _newVaultManagerAddress);
    event COLTokenAddressChanged(address _newCOLTokenAddress);
    event ActivePoolBAIDebtUpdated(uint _BAIDebt);
    event ActivePoolCOLBalanceUpdated(uint _COL);

    // --- Functions ---
    function sendCOL(address _account, uint _amount) external;
    function sendCOLToCollSurplusPool(ICollSurplusPool _collSurplusPool, uint _amount) external;
    function sendCOLToDefaultPool(IDefaultPool _defaultPool, uint _amount) external;
    function sendCOLToStabilityPool(IStabilityPool _stabilityPool, uint _amount) external;
}
