// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from '../access/Ownable.sol';

/// Refer: https://docs.synthetix.io/contracts/RewardsDistributionRecipient
abstract contract RewardsDistributionRecipient is Ownable {
    /**
     * State variables.
     */

    address public rewardsDistribution;

    // function notifyRewardAmount(uint256 reward) external virtual;

    /**
     * Modifer.
     */

    modifier onlyRewardsDistribution() {
        require(
            msg.sender == rewardsDistribution,
            'Caller is not RewardsDistribution contract'
        );
        _;
    }

    /**
     * External.
     */

    function setRewardsDistribution(address _rewardsDistribution)
        external
        onlyOwner
    {
        rewardsDistribution = _rewardsDistribution;
    }
}
