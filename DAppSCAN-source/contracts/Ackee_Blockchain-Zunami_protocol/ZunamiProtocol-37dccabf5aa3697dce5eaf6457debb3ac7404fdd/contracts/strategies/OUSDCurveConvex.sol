//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Constants.sol";
import "./BaseCurveConvex2.sol";

contract OUSDCurveConvex is BaseCurveConvex2 {
    constructor()
    BaseCurveConvex2(
        Constants.CRV_OUSD_ADDRESS,
        Constants.CRV_OUSD_LP_ADDRESS,
        Constants.CVX_OUSD_REWARDS_ADDRESS,
        Constants.CVX_OUSD_PID,
        Constants.OUSD_ADDRESS,
        Constants.CRV_OUSD_EXTRA_ADDRESS,
        Constants.OUSD_EXTRA_ADDRESS,
        Constants.OUSD_EXTRA_PAIR_ADDRESS
    )
    {}
}
