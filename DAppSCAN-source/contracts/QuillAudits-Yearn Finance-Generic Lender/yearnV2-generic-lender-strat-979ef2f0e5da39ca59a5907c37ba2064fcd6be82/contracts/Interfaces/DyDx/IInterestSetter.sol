// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {Interest} from "./ISoloMargin.sol";

/**
 * @title IInterestSetter
 * @author dYdX
 *
 * Interface that Interest Setters for Solo must implement in order to report interest rates.
 */
interface IInterestSetter {
    // ============ Public Functions ============

    /**
     * Get the interest rate of a token given some borrowed and supplied amounts
     *
     * @param  token        The address of the ERC20 token for the market
     * @param  borrowWei    The total borrowed token amount for the market
     * @param  supplyWei    The total supplied token amount for the market
     * @return              The interest rate per second
     */
    function getInterestRate(
        address token,
        uint256 borrowWei,
        uint256 supplyWei
    ) external view returns (Interest.Rate memory);
}
