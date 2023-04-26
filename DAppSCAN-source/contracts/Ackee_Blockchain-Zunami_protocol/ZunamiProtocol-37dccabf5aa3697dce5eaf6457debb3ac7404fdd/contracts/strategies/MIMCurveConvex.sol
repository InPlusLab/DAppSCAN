//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Constants.sol";
import "./BaseCurveConvex2.sol";

contract MIMCurveConvex is BaseCurveConvex2 {
    constructor()
        BaseCurveConvex2(
            Constants.CRV_MIM_ADDRESS,
            Constants.CRV_MIM_LP_ADDRESS,
            Constants.CVX_MIM_REWARDS_ADDRESS,
            Constants.CVX_MIM_PID,
            Constants.MIM_ADDRESS,
            Constants.CVX_MIM_EXTRA_ADDRESS,
            Constants.MIM_EXTRA_ADDRESS,
            Constants.MIM_EXTRA_PAIR_ADDRESS
        )
    {}
}
