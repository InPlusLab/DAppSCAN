// SPDX-License-Identifier: BSL-1.1
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;

/// @title Price oracle interface
interface IPriceOracle {

    // Emits each time new configurator is set up
    event NewPriceFeed(address indexed token, address indexed priceFeed);

    /**
     * @dev Sets price feed if it doesn't exists
     * If pricefeed exists, it changes nothing
     * This logic is done to protect Gearbox from priceOracle attack
     * when potential attacker can get access to price oracle, change them to fraud ones
     * and then liquidate all funds
     * @param token Address of token
     * @param priceFeedToken Address of chainlink price feed token => Eth
     */
    function addPriceFeed(address token, address priceFeedToken) external;

    /**
     * @dev Converts one asset into another using rate. Reverts if price feed doesn't exist
     *
     * @param amount Amount to convert
     * @param tokenFrom Token address converts from
     * @param tokenTo Token address - converts to
     * @return Amount converted to tokenTo asset
     */
    function convert(
        uint256 amount,
        address tokenFrom,
        address tokenTo
    ) external view returns (uint256);

    /**
     * @dev Gets token rate with 18 decimals. Reverts if priceFeed doesn't exist
     *
     * @param tokenFrom Converts from token address
     * @param tokenTo Converts to token address
     * @return Rate in WAD format
     */
    function getLastPrice(address tokenFrom, address tokenTo)
        external
        view
        returns (uint256);
}
