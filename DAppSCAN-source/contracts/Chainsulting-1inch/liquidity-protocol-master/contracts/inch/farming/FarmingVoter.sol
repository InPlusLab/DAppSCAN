// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./FarmingRewards.sol";
import "../../interfaces/IMooniswapFactoryGovernance.sol";

/// @title Allows to vote on multiple predefined farms in one transaction
contract FarmingVoter {
    IMooniswapFactoryGovernance public immutable factory;

    constructor(IMooniswapFactoryGovernance _factory) public {
        factory = _factory;
    }

    function vote(uint256 filter) external returns(uint256) {
        FarmingRewards[5] memory farms = [
            FarmingRewards(0x4dab1Ba9609C1546A0A69a76F00eD935b0b9C45e),
            FarmingRewards(0x0DA1b305d7101359434d71eCEAab71E1fF5437e6),
            FarmingRewards(0xA83fCeA9229C7f1e02Acb46ABe8D6889259339e8),
            FarmingRewards(0x98484d4259A70B73af58180521f2eB71a3F00Ae6),
            FarmingRewards(0x9070832CF729A5150BB26825c2927e7D343EabD9)
        ];

        (,uint104 targetFee,) = factory.virtualDefaultFee();
        for (uint i = 0; i < farms.length; i++) {
            if (filter & (1 << i) != 0) {
                continue;
            }

            uint256 fee = farms[i].fee();
            uint256 diff = (fee > targetFee) ? fee - targetFee : targetFee - fee;
            if (diff*1e18/fee > 0.10e18) { // 10%
                farms[i].discardFeeVote();
                farms[i].discardSlippageFeeVote();
                farms[i].discardDecayPeriodVote();
            } else {
                filter |= (1 << i);
            }
        }

        return filter;
    }
}
