//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./TimelockUtils.sol";
import "./interfaces/IApi3Pool.sol";

/// @title API3 pool contract
/// @notice Users can stake API3 tokens at the pool contract to be granted
/// shares. These shares are exposed to the Aragon-based DAO with a MiniMe
/// token interface, giving the user voting power at the DAO. Staking pays out
/// weekly rewards that get unlocked after a year, and staked funds are used to
/// collateralize an insurance product that is outside the scope of this
/// contract.
/// @dev Functionalities of the contract are distributed to files that form a
/// chain of inheritance:
/// (1) Api3Pool.sol
/// (2) TimelockUtils.sol
/// (3) ClaimUtils.sol
/// (4) StakeUtils.sol
/// (5) TransferUtils.sol
/// (6) DelegationUtils.sol
/// (7) RewardUtils.sol
/// (8) GetterUtils.sol
/// (9) StateUtils.sol
contract Api3Pool is TimelockUtils, IApi3Pool {
    /// @param api3TokenAddress API3 token contract address
    constructor(address api3TokenAddress)
        StateUtils(api3TokenAddress)
    {}
}
