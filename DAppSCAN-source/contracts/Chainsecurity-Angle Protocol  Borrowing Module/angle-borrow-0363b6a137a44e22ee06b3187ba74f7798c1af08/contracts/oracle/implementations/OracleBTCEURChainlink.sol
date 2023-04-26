// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../BaseOracleChainlinkMulti.sol";

/// @title OracleBTCEURChainlink
/// @author Angle Core Team
/// @notice Gives the price of BTC in Euro in base 18
contract OracleBTCEURChainlink is BaseOracleChainlinkMulti {
    uint256 public constant OUTBASE = 10**18;
    string public constant DESCRIPTION = "BTC/EUR Oracle";

    /// @notice Constructor of the contract
    /// @param _stalePeriod Minimum feed update frequency for the oracle to not revert
    /// @param _treasury Treasury associated to the `VaultManager` which reads from this feed
    constructor(uint32 _stalePeriod, address _treasury) BaseOracleChainlinkMulti(_stalePeriod, _treasury) {}

    /// @inheritdoc IOracle
    function read() external view override returns (uint256 quoteAmount) {
        quoteAmount = OUTBASE;
        AggregatorV3Interface[2] memory circuitChainlink = [
            // Oracle BTC/USD
            AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c),
            // Oracle EUR/USD
            AggregatorV3Interface(0xb49f677943BC038e9857d61E7d053CaA2C1734C1)
        ];
        uint8[2] memory circuitChainIsMultiplied = [1, 0];
        uint8[2] memory chainlinkDecimals = [8, 8];
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
