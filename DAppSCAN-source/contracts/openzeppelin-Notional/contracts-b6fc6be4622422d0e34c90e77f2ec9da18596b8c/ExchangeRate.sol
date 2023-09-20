// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../lib/SafeInt256.sol";
import "../lib/SafeMath.sol";
import "../utils/Common.sol";
import "../interface/IAggregator.sol";

import "@openzeppelin/contracts/utils/SafeCast.sol";


library ExchangeRate {
    using SafeInt256 for int256;
    using SafeMath for uint256;

    /**
     * Exchange rates between currencies
     */
    struct Rate {
        // The address of the chainlink price oracle
        address rateOracle;
        // The decimals of precision that the rate oracle uses
        uint128 rateDecimals;
        // True of the exchange rate must be inverted
        bool mustInvert;
        // Amount of buffer to apply to the exchange rate, this defines the collateralization ratio
        // between the two currencies. This must be stored with 18 decimal precision because it is used
        // to convert to an ETH balance.
        uint128 buffer;
    }

    /**
     * @notice Converts a balance between token addresses.
     *
     * @param er exchange rate object from base to ETH
     * @param baseDecimals decimals for base currency
     * @param balance amount to convert
     * @return the converted balance denominated in ETH with 18 decimal places
     */
    function _convertToETH(
        Rate memory er,
        uint256 baseDecimals,
        int256 balance,
        bool buffer
    ) internal view returns (int256) {
        // Fetches the latest answer from the chainlink oracle and buffer it by the apporpriate amount.
        uint256 rate = _fetchExchangeRate(er, false);
        uint128 absBalance = uint128(balance.abs());
//SWC-135-Code With No Effects:L49
        // We are converting to ETH here so we know that it has Common.DECIMAL precision. The calculation here is:
        // baseDecimals * rateDecimals * Common.DECIMAL /  (rateDecimals * baseDecimals)
        // er.buffer is in Common.DECIMAL precision
        // We use uint256 to do the calculation and then cast back to int256 to avoid overflows.
        int256 result = int256(
            SafeCast.toUint128(rate
                .mul(absBalance)
                // Buffer has 18 decimal places of precision
                .mul(buffer ? er.buffer : Common.DECIMALS)
                .div(er.rateDecimals)
                .div(baseDecimals)
            )
        );

        return balance > 0 ? result : result.neg();
    }

    /**
     * @notice Converts the balance denominated in ETH to the equivalent value in base.
     * @param er exchange rate object from base to ETH
     * @param baseDecimals decimals for base currency
     * @param balance amount (denominated in ETH) to convert
     */
    function _convertETHTo(
        Rate memory er,
        uint256 baseDecimals,
        int256 balance
    ) internal view returns (int256) {
        uint256 rate = _fetchExchangeRate(er, true);
        uint128 absBalance = uint128(balance.abs());

        // We are converting from ETH here so we know that it has Common.DECIMAL precision. The calculation here is:
        // ethDecimals * rateDecimals * baseDecimals / (ethDecimals * rateDecimals)
        // er.buffer is in Common.DECIMAL precision
        // We use uint256 to do the calculation and then cast back to int256 to avoid overflows.
        int256 result = int256(
            SafeCast.toUint128(rate
                .mul(absBalance)
                .mul(baseDecimals)
                .div(Common.DECIMALS)
                .div(er.rateDecimals)
            )
        );

        return balance > 0 ? result : result.neg();
    }

    function _fetchExchangeRate(Rate memory er, bool invert) internal view returns (uint256) {
        int256 rate = IAggregator(er.rateOracle).latestAnswer();
        require(rate > 0, $$(ErrorCode(INVALID_EXCHANGE_RATE)));

        if (invert || (er.mustInvert && !invert)) {
            // If the ER is inverted and we're NOT asking to invert then we need to invert the rate here.
            return uint256(er.rateDecimals).mul(er.rateDecimals).div(uint256(rate));
        }

        return uint256(rate);
    }

    /**
     * @notice Calculates the exchange rate between two currencies via ETH. Returns the rate.
     */
    function _exchangeRate(Rate memory baseER, Rate memory quoteER, uint16 quote) internal view returns (uint256) {
        uint256 rate = _fetchExchangeRate(baseER, false);

        if (quote != 0) {
            uint256 quoteRate = _fetchExchangeRate(quoteER, false);

            rate = rate.mul(quoteER.rateDecimals).div(quoteRate);
        }

        return rate;
    }

}