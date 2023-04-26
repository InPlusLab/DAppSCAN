//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Constants.sol";
import "./BaseCurveConvex2.sol";

contract USDKCurveConvex is BaseCurveConvex2 {
    constructor()
        BaseCurveConvex2(
            Constants.CRV_USDK_ADDRESS,
            Constants.CRV_USDK_LP_ADDRESS,
            Constants.CVX_USDK_REWARDS_ADDRESS,
            Constants.CVX_USDK_PID,
            Constants.USDK_ADDRESS,
            address(0),
            address(0),
            address(0)
        )
    {}
}
