pragma solidity 0.5.16;

interface BankConfig {
    /// @dev Return minimum ETH debt size per position.
    function minDebtSize() external view returns (uint256);

    /// @dev Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);

    /// @dev Return the bps rate for reserve pool.
    function getReservePoolBps() external view returns (uint256);

    /// @dev Return the bps rate for Avada Kill caster.
    function getKillBps() external view returns (uint256);

    /// @dev Return whether the given address is a goblin.
    function isGoblin(address goblin) external view returns (bool);

    /// @dev Return whether the given goblin accepts more debt. Revert on non-goblin.
    function acceptDebt(address goblin) external view returns (bool);

    /// @dev Return the work factor for the goblin + ETH debt, using 1e4 as denom. Revert on non-goblin.
    function workFactor(address goblin, uint256 debt) external view returns (uint256);

    /// @dev Return the kill factor for the goblin + ETH debt, using 1e4 as denom. Revert on non-goblin.
    function killFactor(address goblin, uint256 debt) external view returns (uint256);
}
