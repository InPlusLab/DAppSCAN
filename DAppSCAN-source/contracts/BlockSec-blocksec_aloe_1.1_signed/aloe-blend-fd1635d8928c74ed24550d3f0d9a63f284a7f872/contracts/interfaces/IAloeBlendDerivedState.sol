// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IAloeBlendDerivedState {
    /**
     * @notice Calculates the vault's total holdings - in other words, how much of each token
     * the vault would hold if it withdrew all its liquidity from Uniswap and Compound.
     * @return inventory0 The amount of token0, as of last poke
     * @return inventory1 The amount of token1, as of last poke
     */
    function getInventory() external view returns (uint256 inventory0, uint256 inventory1);

    /**
     * @notice Calculates a rebalance urgency level between 0 and 10000. Caller's reward is
     * proportional to this value.
     * @return urgency How badly the vault wants its `rebalance()` function to be called
     */
    function getRebalanceUrgency() external view returns (uint32 urgency);

    /**
     * @notice Calculates what the Uniswap position's width *should* be based on current volatility
     * @return width The width as a number of ticks
     * @return tickTWAP The geometric mean tick spanning 6 minutes ago -> now
     */
    // function getNextPositionWidth() external view returns (uint24 width, int24 tickTWAP);
}
