//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ExtendedMath.sol";

/// @dev This is a sigmoid bonding curve implementation to calculate buying and selling amounts
/// Formulas are inspired from https://medium.com/molecule-blog/designing-different-fundraising-scenarios-with-sigmoidal-token-bonding-curves-ceafc734ed97
contract Sigmoid {
    using ExtendedMath for int256;

    function n1(
        int256 a,
        int256 b,
        int256 c,
        int256 newReserves
    ) internal pure returns (int256) {
        return 2 * a.pow2() * b * newReserves * (b.pow2() + c).sqrt();
    }

    function n2(
        int256 a,
        int256 b,
        int256,
        int256 newReserves
    ) internal pure returns (int256) {
        return 2 * a.pow2() * b.pow2() * newReserves;
    }

    function n3(
        int256 a,
        int256,
        int256 c,
        int256 newReserves
    ) internal pure returns (int256) {
        return 2 * a.pow2() * c * newReserves;
    }

    function n4(
        int256 a,
        int256 b,
        int256 c,
        int256 newReserves
    ) internal pure returns (int256) {
        return a * newReserves.pow2() * (b.pow2() + c).sqrt();
    }

    function n5(
        int256 a,
        int256 b,
        int256,
        int256 newReserves
    ) internal pure returns (int256) {
        return 1 * a * b * newReserves.pow2();
    }

    function n6(
        int256,
        int256,
        int256,
        int256 newReserves
    ) internal pure returns (int256) {
        return newReserves.pow3();
    }

    function d1(
        int256 a,
        int256 b,
        int256 c,
        int256 newReserves
    ) internal pure returns (int256) {
        return
            a *
            (-2 *
                a.pow2() *
                c -
                4 *
                a *
                b *
                newReserves +
                2 *
                newReserves.pow2());
    }

    /// @dev Buying into the curve with payment tokens will return Tokens amount to be bought
    /// @param a maxPrice of the curve / 2
    /// @param b inflectionPoint of the curve
    /// @param c slope steepness of the curve
    /// @param currentTokensSupply current amount of Tokens in the curve
    /// @param paymentReserves current mount of payment reserves in the curve
    /// @param paymentToSpend amount the of payment tokens to buy Tokens with
    function calculateTokensBoughtFromPayment(
        int256 a,
        int256 b,
        int256 c,
        int256 currentTokensSupply,
        int256 paymentReserves,
        int256 paymentToSpend
    ) public pure returns (uint256) {
        // The amount of reserves after payment is made
        int256 newReserves = paymentReserves + paymentToSpend;

        // Calculations cause "stack too deep" so are broken into individual numerator and denominator functions
        int256 newSupply = (n6(a, b, c, newReserves) +
            n4(a, b, c, newReserves) -
            n1(a, b, c, newReserves) -
            n2(a, b, c, newReserves) -
            n3(a, b, c, newReserves) -
            n5(a, b, c, newReserves)) / (d1(a, b, c, newReserves));

        // Return the difference
        return uint256(newSupply - currentTokensSupply);
    }

    /// @dev Selling Tokens into the curve will return payment tokens to be refunded
    /// @param a maxPrice of the curve / 2
    /// @param b inflectionPoint of the curve
    /// @param c slope steepness of the curve
    /// @param currentTokenSupply current amount of Tokens in the curve
    /// @param paymentReserves current mount of payment reserves in the curve
    /// @param tokensToSell amount the of Tokens the user wants to sell
    function calculatePaymentReturnedFromTokens(
        int256 a,
        int256 b,
        int256 c,
        int256 currentTokenSupply,
        int256 paymentReserves,
        int256 tokensToSell
    ) public pure returns (uint256) {
        // Supply after Tokens are sold
        int256 newSupply = currentTokenSupply - tokensToSell;

        // Calc the constant at supply = 0
        int256 constantVal = a * ((b.pow2() + c).sqrt());

        // Calculate the new reserve amount
        int256 newReserves = (a *
            (((b - newSupply).pow2() + c).sqrt() + newSupply)) - constantVal;

        // Return the difference
        return uint256(paymentReserves - newReserves);
    }
}
