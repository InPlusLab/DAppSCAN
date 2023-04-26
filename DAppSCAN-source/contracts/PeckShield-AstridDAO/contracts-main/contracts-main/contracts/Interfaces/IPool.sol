// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

// Common interface for the Pools.
interface IPool {
    
    // --- Events ---
    
    event COLBalanceUpdated(uint _newBalance);
    event BAIBalanceUpdated(uint _newBalance);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event DefaultPoolAddressChanged(address _newDefaultPoolAddress);
    event StabilityPoolAddressChanged(address _newStabilityPoolAddress);
    event COLSent(address _to, uint _amount);

    // --- Functions ---
    
    function getCOL() external view returns (uint);

    function getBAIDebt() external view returns (uint);

    function increaseBAIDebt(uint _amount) external;

    function decreaseBAIDebt(uint _amount) external;

    // --- For support of ERC20 ---
    function receiveCOL(uint _amount) external;
    // Fallback payment functions should be disabled.
}
