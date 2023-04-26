//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Constants.sol";
import "./BaseCurveConvex.sol";

contract AaveCurveConvex is BaseCurveConvex {
    constructor()
        BaseCurveConvex(
            Constants.CRV_AAVE_ADDRESS,
            Constants.CRV_AAVE_LP_ADDRESS,
            Constants.CVX_AAVE_REWARDS_ADDRESS,
            Constants.CVX_AAVE_PID,
            Constants.CVX_AAVE_EXTRA_ADDRESS,
            Constants.AAVE_EXTRA_ADDRESS,
            Constants.AAVE_EXTRA_PAIR_ADDRESS
        )
    {}
}
