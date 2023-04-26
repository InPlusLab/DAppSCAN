// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IFraxFarmUniV3 {
    
    struct LockedNFT {
        uint256 token_id; // for Uniswap V3 LPs
        uint256 liquidity;
        uint256 start_timestamp;
        uint256 ending_timestamp;
        uint256 lock_multiplier; // 6 decimals of precision. 1x = 1000000
        int24 tick_lower;
        int24 tick_upper;
    }

    function owner() external view returns (address);
    function stakingToken() external view returns (address);
    function uni_token0() external view returns (address);
    function uni_token1() external view returns (address);
    function uni_tick_lower() external view returns (int24);
    function uni_tick_upper() external view returns (int24);
    function uni_required_fee() external view returns (uint24);
    function fraxPerLPToken() external view returns (uint256);
    function calcCurCombinedWeight(address account) external view
        returns (
            uint256 old_combined_weight,
            uint256 new_vefxs_multiplier,
            uint256 new_combined_weight
        );
    function lockedNFTsOf(address account) external view returns (LockedNFT[] memory);
    function lockedNFTsOfLength(address account) external view returns (uint256);
    function lockAdditional(uint256 token_id, uint256 token0_amt, uint256 token1_amt,uint256 token0_min_in, uint256 token1_min_in, bool use_balof_override) external;
    function stakeLocked(uint256 token_id, uint256 secs) external;
    function withdrawLocked(uint256 token_id, address destination_address) external;



    function periodFinish() external view returns (uint256);
    function getAllRewardTokens() external view returns (address[] memory);
    function earned(address account) external view returns (uint256[] memory new_earned);
    function totalLiquidityLocked() external view returns (uint256);
    function lockedLiquidityOf(address account) external view returns (uint256);
    function totalCombinedWeight() external view returns (uint256);
    function combinedWeightOf(address account) external view returns (uint256);
    function lockMultiplier(uint256 secs) external view returns (uint256);
    function rewardRates(uint256 token_idx) external view returns (uint256 rwd_rate);

    function userStakedFrax(address account) external view returns (uint256);
    function proxyStakedFrax(address proxy_address) external view returns (uint256);
    function maxLPForMaxBoost(address account) external view returns (uint256);
    function minVeFXSForMaxBoost(address account) external view returns (uint256);
    function minVeFXSForMaxBoostProxy(address proxy_address) external view returns (uint256);
    function veFXSMultiplier(address account) external view returns (uint256 vefxs_multiplier);

    function toggleValidVeFXSProxy(address proxy_address) external;
    function proxyToggleStaker(address staker_address) external;
    function stakerSetVeFXSProxy(address proxy_address) external;
    function getReward(address destination_address) external returns (uint256[] memory);
    function getReward(address destination_address, bool also_claim_extra) external returns (uint256[] memory);
    function vefxs_max_multiplier() external view returns(uint256);
    function vefxs_boost_scale_factor() external view returns(uint256);
    function vefxs_per_frax_for_max_boost() external view returns(uint256);

    function sync() external;
}
