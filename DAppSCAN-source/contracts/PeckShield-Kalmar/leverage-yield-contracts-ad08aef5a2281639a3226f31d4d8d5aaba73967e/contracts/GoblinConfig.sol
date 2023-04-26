pragma solidity 0.5.16;

interface GoblinConfig {
    /// @dev Return whether the given goblin accepts more debt.
    function acceptDebt(address goblin) external view returns (bool);
    /// @dev Return the work factor for the goblin + ETH debt, using 1e4 as denom.
    function workFactor(address goblin, uint256 debt) external view returns (uint256);
    /// @dev Return the kill factor for the goblin + ETH debt, using 1e4 as denom.
    function killFactor(address goblin, uint256 debt) external view returns (uint256);
}
