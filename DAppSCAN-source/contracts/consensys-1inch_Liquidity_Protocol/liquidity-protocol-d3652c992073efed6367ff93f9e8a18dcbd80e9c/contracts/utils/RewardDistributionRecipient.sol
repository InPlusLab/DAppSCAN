// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";


abstract contract RewardDistributionRecipient is Ownable {
    address public rewardDistribution;

    function notifyRewardAmount(uint256 reward) external virtual;

    modifier onlyRewardDistribution() {
        require(_msgSender() == rewardDistribution, "Access denied");
        _;
    }

    function setRewardDistribution(address _rewardDistribution) external onlyOwner {
        rewardDistribution = _rewardDistribution;
    }
}
