//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Constants.sol";
import "./BaseCurveConvex2.sol";

contract DUSDCurveConvex is BaseCurveConvex2 {
    constructor()
        BaseCurveConvex2(
            Constants.CRV_DUSD_ADDRESS,
            Constants.CRV_DUSD_LP_ADDRESS,
            Constants.CVX_DUSD_REWARDS_ADDRESS,
            Constants.CVX_DUSD_PID,
            Constants.DUSD_ADDRESS,
            Constants.CVX_DUSD_EXTRA_ADDRESS,
            Constants.DUSD_EXTRA_ADDRESS,
            Constants.DUSD_EXTRA_PAIR_ADDRESS
        )
    {}
}
