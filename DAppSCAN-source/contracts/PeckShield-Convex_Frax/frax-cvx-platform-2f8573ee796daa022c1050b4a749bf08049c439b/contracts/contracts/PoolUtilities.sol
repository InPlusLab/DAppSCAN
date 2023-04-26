// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IFraxFarmERC20.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';


/*
This is a utility library which is mainly used for off chain calculations
*/
contract PoolUtilities{
    address public constant convexProxy = address(0x59CFCD384746ec3035299D90782Be065e466800B);
    address public constant vefxs = address(0xc8418aF6358FFddA74e09Ca9CC3Fe03Ca6aDC5b0);

    //get weighted reward rates of a specific staking contract(rate per weight unit)
    function weightedRewardRates(address _stakingAddress) public view returns (uint256[] memory weightedRates) {
        //get list of reward tokens
        address[] memory rewardTokens = IFraxFarmERC20(_stakingAddress).getAllRewardTokens();
        //get total weight of all stakers
        uint256 totalWeight = IFraxFarmERC20(_stakingAddress).totalCombinedWeight();

        weightedRates = new uint256[](rewardTokens.length);

        if(totalWeight == 0) return weightedRates;

        //calc weighted reward rates
        for (uint256 i = 0; i < rewardTokens.length; i++){ 
            weightedRates[i] = IFraxFarmERC20(_stakingAddress).rewardRates(i) * 1e18 / totalWeight;
        }
    }

    //get boosted reward rate of user at a specific staking contract
    //returns amount user receives per second based on weight/liq ratio
    //%return = userBoostedRewardRate * timeFrame * price of reward / price of LP / 1e18
    function userBoostedRewardRates(address _stakingAddress, address _vaultAddress) external view returns (uint256[] memory boostedRates) {
        //get list of reward tokens
        uint256[] memory wrr = weightedRewardRates(_stakingAddress);

        //get user liquidity and weight
        uint256 userLiq = IFraxFarmERC20(_stakingAddress).lockedLiquidityOf(_vaultAddress);
        uint256 userWeight = IFraxFarmERC20(_stakingAddress).combinedWeightOf(_vaultAddress);

        boostedRates = new uint256[](wrr.length);

        if(userLiq == 0) return boostedRates;

        //calc boosted rates
        for (uint256 i = 0; i < wrr.length; i++){ 
            boostedRates[i] = wrr[i] * userWeight / userLiq;
        }
    }

    
    //get convex vefxs multiplier for a specific staking contract
    function veFXSMultiplier(address _stakingAddress) public view returns (uint256 vefxs_multiplier) {
        uint256 vefxs_bal_to_use = IERC20(vefxs).balanceOf(convexProxy);
        uint256 vefxs_max_multiplier = IFraxFarmERC20(_stakingAddress).vefxs_max_multiplier();

        // First option based on fraction of total veFXS supply, with an added scale factor
        uint256 mult_optn_1 = (vefxs_bal_to_use * vefxs_max_multiplier * IFraxFarmERC20(_stakingAddress).vefxs_boost_scale_factor()) 
                            / (IERC20(vefxs).totalSupply() * 1e18);

        // Second based on old method, where the amount of FRAX staked comes into play
        uint256 mult_optn_2;
        {
            uint256 veFXS_needed_for_max_boost;

            // Need to use proxy-wide FRAX balance if applicable, to prevent exploiting
            veFXS_needed_for_max_boost = IFraxFarmERC20(_stakingAddress).minVeFXSForMaxBoostProxy(convexProxy);

            if (veFXS_needed_for_max_boost > 0){ 
                uint256 user_vefxs_fraction = (vefxs_bal_to_use * 1e18) / veFXS_needed_for_max_boost;
                
                mult_optn_2 = (user_vefxs_fraction * vefxs_max_multiplier) / 1e18;
            }
            else mult_optn_2 = 0; // This will happen with the first stake, when user_staked_frax is 0
        }

        // Select the higher of the two
        vefxs_multiplier = (mult_optn_1 > mult_optn_2 ? mult_optn_1 : mult_optn_2);

        // Cap the boost to the vefxs_max_multiplier
        if (vefxs_multiplier > vefxs_max_multiplier) vefxs_multiplier = vefxs_max_multiplier;
    }
}
