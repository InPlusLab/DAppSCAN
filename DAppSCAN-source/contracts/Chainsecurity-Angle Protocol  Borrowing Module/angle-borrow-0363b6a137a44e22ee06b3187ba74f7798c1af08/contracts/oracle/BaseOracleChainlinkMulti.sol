// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../interfaces/IOracle.sol";
import "../interfaces/ITreasury.sol";

/// @title BaseOracleChainlinkMulti
/// @author Angle Core Team
/// @notice Base Contract to be overriden by all contracts of the protocol
/// @dev This base contract concerns an oracle that uses Chainlink with multiple pools to read from
/// @dev All gas-efficient implementation of the `OracleChainlinkMulti` contract should inherit from this
abstract contract BaseOracleChainlinkMulti is IOracle {
    // ========================= Parameters and References =========================

    /// @inheritdoc IOracle
    ITreasury public override treasury;
    /// @notice Represent the maximum amount of time (in seconds) between each Chainlink update
    /// before the price feed is considered stale
    uint32 public stalePeriod;

    // =================================== Event ===================================

    event StalePeriodUpdated(uint32 _stalePeriod);

    // =================================== Errors ===================================

    error InvalidChainlinkRate();
    error NotGovernorOrGuardian();
    error NotVaultManagerOrGovernor();

    /// @notice Constructor for an oracle using Chainlink with multiple pools to read from
    /// @param _stalePeriod Minimum feed update frequency for the oracle to not revert
    /// @param _treasury Treasury associated to the VaultManager which reads from this feed
    constructor(uint32 _stalePeriod, address _treasury) {
        stalePeriod = _stalePeriod;
        treasury = ITreasury(_treasury);
    }

    // ============================= Reading Oracles ===============================

    /// @inheritdoc IOracle
    function read() external view virtual override returns (uint256 quoteAmount);

    /// @notice Reads a Chainlink feed using a quote amount and converts the quote amount to
    /// the out-currency
    /// @param quoteAmount The amount for which to compute the price expressed with base decimal
    /// @param feed Chainlink feed to query
    /// @param multiplied Whether the ratio outputted by Chainlink should be multiplied or divided
    /// to the `quoteAmount`
    /// @param decimals Number of decimals of the corresponding Chainlink pair
    /// @return The `quoteAmount` converted in out-currency
    function _readChainlinkFeed(
        uint256 quoteAmount,
        AggregatorV3Interface feed,
        uint8 multiplied,
        uint256 decimals
    ) internal view returns (uint256) {
        (uint80 roundId, int256 ratio, , uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        if (ratio <= 0 || roundId > answeredInRound || block.timestamp - updatedAt > stalePeriod)
            revert InvalidChainlinkRate();
        uint256 castedRatio = uint256(ratio);
        // Checking whether we should multiply or divide by the ratio computed
        if (multiplied == 1) return (quoteAmount * castedRatio) / (10**decimals);
        else return (quoteAmount * (10**decimals)) / castedRatio;
    }

    // ======================= Governance Related Functions ========================

    /// @notice Changes the stale period
    /// @param _stalePeriod New stale period (in seconds)
    function changeStalePeriod(uint32 _stalePeriod) external {
        if (!treasury.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        stalePeriod = _stalePeriod;
        emit StalePeriodUpdated(_stalePeriod);
    }

    /// @inheritdoc IOracle
    function setTreasury(address _treasury) external override {
        if (!treasury.isVaultManager(msg.sender) && !treasury.isGovernor(msg.sender))
            revert NotVaultManagerOrGovernor();
        treasury = ITreasury(_treasury);
    }
}
