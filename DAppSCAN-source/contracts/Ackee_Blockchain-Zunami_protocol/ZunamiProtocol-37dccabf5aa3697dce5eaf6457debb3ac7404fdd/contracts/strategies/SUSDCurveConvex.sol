//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Constants.sol";
import "./BaseCurveConvex4.sol";

contract SUSDCurveConvex is BaseCurveConvex4 {
    constructor()
        BaseCurveConvex4(
            Constants.CRV_SUSD_ADDRESS,
            Constants.CRV_SUSD_LP_ADDRESS,
            Constants.CVX_SUSD_REWARDS_ADDRESS,
            Constants.CVX_SUSD_PID,
            Constants.SUSD_ADDRESS,
            Constants.CVX_SUSD_EXTRA_ADDRESS,
            Constants.SUSD_EXTRA_ADDRESS,
            Constants.SUSD_EXTRA_PAIR_ADDRESS
        )
    {}
}
