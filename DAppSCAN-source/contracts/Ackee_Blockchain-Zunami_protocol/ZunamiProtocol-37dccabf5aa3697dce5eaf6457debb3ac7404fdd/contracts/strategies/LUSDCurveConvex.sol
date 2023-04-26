//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Constants.sol";
import "./BaseCurveConvex2.sol";

contract LUSDCurveConvex is BaseCurveConvex2 {
    constructor()
        BaseCurveConvex2(
            Constants.CRV_LUSD_ADDRESS,
            Constants.CRV_LUSD_LP_ADDRESS,
            Constants.CVX_LUSD_REWARDS_ADDRESS,
            Constants.CVX_LUSD_PID,
            Constants.LUSD_ADDRESS,
            Constants.CVX_LUSD_EXTRA_ADDRESS,
            Constants.LUSD_EXTRA_ADDRESS,
            Constants.LUSD_EXTRA_PAIR_ADDRESS
        )
    {}
}
