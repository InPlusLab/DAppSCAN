pragma solidity ^0.4.24;

/**
 * @title Library to handle implementation of different reward models
 * @author Nikola Madjarevic
 */
library IncentiveModels {

    /**
     * @notice Implementation of average incentive model, reward is splited equally per referrer
     * @param totalRewardEthWEI is total reward for the influencers
     * @param numberOfInfluencers is how many influencers we're splitting reward between
     */
    function averageModelRewards(
        uint totalRewardEthWEI,
        uint numberOfInfluencers
    ) internal pure returns (uint) {
        if(numberOfInfluencers > 0) {
            uint equalPart = totalRewardEthWEI / numberOfInfluencers;
            return equalPart;
        }
        return 0;
    }

    /**
     * @notice Implementation similar to average incentive model, except direct referrer) - gets 3x as the others
     * @param totalRewardEthWEI is total reward for the influencers
     * @param numberOfInfluencers is how many influencers we're splitting reward between
     * @return two values, first is reward per regular referrer, and second is reward for last referrer in the chain
     */
    function averageLast3xRewards(
        uint totalRewardEthWEI,
        uint numberOfInfluencers
    ) internal pure returns (uint,uint) {
        if(numberOfInfluencers> 0) {
            uint rewardPerReferrer = totalRewardEthWEI / (numberOfInfluencers + 2);
            uint rewardForLast = rewardPerReferrer*3;
            return (rewardPerReferrer, rewardForLast);
        }
        return (0,0);
    }

    /**
     * @notice Function to return array of corresponding values with rewards in power law schema
     * @param totalRewardEthWEI is totalReward
     * @param numberOfInfluencers is the total number of influencers
     * @return rewards in wei
     */
    function powerLawRewards(
        uint totalRewardEthWEI,
        uint numberOfInfluencers,
        uint factor
    ) internal pure returns (uint[]) {
        uint[] memory rewards = new uint[](numberOfInfluencers);
        if(numberOfInfluencers > 0) {
            uint x = calculateX(totalRewardEthWEI,numberOfInfluencers,factor);
            for(uint i=0; i<numberOfInfluencers;i++) {
                rewards[numberOfInfluencers-i-1] = x / (2**i);
            }
        }
        return rewards;
    }


    /**
     * @notice Function to calculate base for all rewards in power law model
     * @param sumWei is the total reward to be splited in Wei
     * @param numberOfElements is the number of referrers in the chain
     * @return wei value of base for the rewards in power law
     */
    function calculateX(
        uint sumWei,
        uint numberOfElements,
        uint factor
    ) private pure returns (uint) {
        uint a = 1;
        uint sumOfFactors = 1;
        for(uint i=1; i<numberOfElements; i++) {
            a = a*factor;
            sumOfFactors += a;
        }
        return (sumWei*a) / sumOfFactors;
    }
}
