// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./BaseOracleChainlinkMulti.sol";

/// @title OracleChainlinkMulti
/// @author Angle Core Team
/// @notice Oracle contract, one contract is deployed per collateral/stablecoin pair
/// @dev This contract concerns an oracle that uses Chainlink with multiple pools to read from
/// @dev Typically we expect to use this contract to read like the ETH/USD and then USD/EUR feed
contract OracleChainlinkMulti is BaseOracleChainlinkMulti {
    // ========================= Parameters and References =========================

    /// @notice Chainlink pools, the order of the pools has to be the order in which they are read for the computation
    /// of the price
    AggregatorV3Interface[] public circuitChainlink;
    /// @notice Whether each rate for the pairs in `circuitChainlink` should be multiplied or divided
    uint8[] public circuitChainIsMultiplied;
    /// @notice Decimals for each Chainlink pairs
    uint8[] public chainlinkDecimals;
    /// @notice Unit of the stablecoin
    uint256 public immutable outBase;
    /// @notice Description of the assets concerned by the oracle and the price outputted
    string public description;

    // ===================================== Error =================================

    error IncompatibleLengths();

    /// @notice Constructor for an oracle using Chainlink with multiple pools to read from
    /// @param _circuitChainlink Chainlink pool addresses (in order)
    /// @param _circuitChainIsMultiplied Whether we should multiply or divide by this rate
    /// @param _outBase Unit of the stablecoin (or the out asset) associated to the oracle
    /// @param _stalePeriod Minimum feed update frequency for the oracle to not revert
    /// @param _treasury Treasury associated to the VaultManager which reads from this feed
    /// @param _description Description of the assets concerned by the oracle
    /// @dev For instance, if this oracle is supposed to give the price of ETH in EUR, and if the agEUR
    /// stablecoin associated to EUR has 18 decimals, then `outBase` should be 10**18
    constructor(
        address[] memory _circuitChainlink,
        uint8[] memory _circuitChainIsMultiplied,
        uint256 _outBase,
        uint32 _stalePeriod,
        address _treasury,
        string memory _description
    ) BaseOracleChainlinkMulti(_stalePeriod, _treasury) {
        outBase = _outBase;
        description = _description;
        uint256 circuitLength = _circuitChainlink.length;
        if (circuitLength == 0 || circuitLength != _circuitChainIsMultiplied.length) revert IncompatibleLengths();
        for (uint256 i = 0; i < circuitLength; i++) {
            AggregatorV3Interface _pool = AggregatorV3Interface(_circuitChainlink[i]);
            circuitChainlink.push(_pool);
            chainlinkDecimals.push(_pool.decimals());
        }
        circuitChainIsMultiplied = _circuitChainIsMultiplied;
    }

    // ============================= Reading Oracles ===============================

    /// @inheritdoc IOracle
    function read() external view override returns (uint256 quoteAmount) {
        quoteAmount = outBase;
        for (uint256 i = 0; i < circuitChainlink.length; i++) {
            quoteAmount = _readChainlinkFeed(
                quoteAmount,
                circuitChainlink[i],
                circuitChainIsMultiplied[i],
                chainlinkDecimals[i]
            );
        }
    }
}
