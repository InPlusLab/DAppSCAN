//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Constants.sol";
import "./BaseCurveConvex2.sol";

contract USDPCurveConvex is BaseCurveConvex2 {
    constructor()
        BaseCurveConvex2(
            Constants.CRV_USDP_ADDRESS,
            Constants.CRV_USDP_LP_ADDRESS,
            Constants.CVX_USDP_REWARDS_ADDRESS,
            Constants.CVX_USDP_PID,
            Constants.USDP_ADDRESS,
            Constants.CVX_USDP_EXTRA_ADDRESS,
            Constants.USDP_EXTRA_ADDRESS,
            Constants.USDP_EXTRA_PAIR_ADDRESS
        )
    {}
}
