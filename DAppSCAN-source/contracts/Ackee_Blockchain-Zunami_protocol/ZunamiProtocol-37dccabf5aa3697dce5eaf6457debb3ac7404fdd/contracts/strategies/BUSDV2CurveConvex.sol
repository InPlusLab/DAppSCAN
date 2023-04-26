//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Constants.sol";
import "./BaseCurveConvex2.sol";

contract BUSDV2CurveConvex is BaseCurveConvex2 {
    constructor()
        BaseCurveConvex2(
            Constants.CRV_BUSDV2_ADDRESS,
            Constants.CRV_BUSDV2_LP_ADDRESS,
            Constants.CVX_BUSDV2_REWARDS_ADDRESS,
            Constants.CVX_BUSDV2_PID,
            Constants.BUSD_ADDRESS,
            address(0),
            address(0),
            address(0)
        )
    {}
}
