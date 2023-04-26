// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface IPriceGetter {
    /**
     * Token buy price at USDC. Amount of USDC we should spend to buy one token.
     * Returned value is [USDC/token]
     * Usage: tokenAmount = usdcAmount * denominator() / getUsdcBuyPrice()
     * Normilized to 10**18
     */
    function getUsdcBuyPrice() external view returns (uint256);

    /**
     * Token sell price at USDC. Amount of USDC we got if sell one token.
     * Returned value is [USDC/token]
     * Usage: usdcAmount = tokenAmount * getUsdcSellPrice() / denominator()
     * Normilized to 10**18
     */
    function getUsdcSellPrice() external view returns (uint256);

    /**
     * Denominator for normalization. Default 10**18.
     */
    function denominator() external view returns (uint256);
}
