//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Constants.sol";
import "./BaseCurveConvex2.sol";

contract MUSDCurveConvex is BaseCurveConvex2 {
    constructor()
        BaseCurveConvex2(
            Constants.CRV_MUSD_ADDRESS,
            Constants.CRV_MUSD_LP_ADDRESS,
            Constants.CVX_MUSD_REWARDS_ADDRESS,
            Constants.CVX_MUSD_PID,
            Constants.MUSD_ADDRESS,
            Constants.CVX_MUSD_EXTRA_ADDRESS,
            Constants.MUSD_EXTRA_ADDRESS,
            Constants.MUSD_EXTRA_PAIR_ADDRESS
        )
    {}
}
