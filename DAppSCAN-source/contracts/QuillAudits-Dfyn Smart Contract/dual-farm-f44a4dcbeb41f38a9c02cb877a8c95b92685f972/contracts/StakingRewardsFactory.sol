// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./StakingRewards.sol";

contract StakingRewardsFactory is Ownable {
    // immutables
    uint256 public stakingRewardsGenesis;

    // the staking tokens for which the rewards contract has been deployed
    address[] public stakingTokens;

    // info about rewards for a particular staking token
    struct StakingRewardsInfo {
        address stakingRewards;
        address[] poolRewardToken;
        uint256[] poolRewardAmount;
    }

    // multiple reward tokens
    //address[] public rewardTokens;

    // rewards info by staking token
    mapping(address => StakingRewardsInfo)
        public stakingRewardsInfoByStakingToken;

    // rewards info by staking token
    mapping(address => uint256) public rewardTokenQuantities;

    // SWC-120-Weak Sources of Randomness from Chain Attributes: L36
    constructor(uint256 _stakingRewardsGenesis) public Ownable() {
        require(
            _stakingRewardsGenesis >= block.timestamp,
            "StakingRewardsFactory::constructor: genesis too soon"
        );
        stakingRewardsGenesis = _stakingRewardsGenesis;
    }

    ///// permissioned functions

    // deploy a staking reward contract for the staking token, and store the reward amount
    // the reward will be distributed to the staking reward contract no sooner than the genesis
    function deploy(
        address stakingToken,
        address[] memory rewardTokens,
        uint256[] memory rewardAmounts
    ) public onlyOwner {
        StakingRewardsInfo storage info =
            stakingRewardsInfoByStakingToken[stakingToken];
        require(
            info.stakingRewards == address(0),
            "StakingRewardsFactory::deploy: already deployed"
        );
        info.stakingRewards = address(
            new StakingRewards(
                /*_rewardsDistribution=*/
                address(this),
                rewardTokens,
                stakingToken
            )
        );

        for (uint8 i = 0; i < rewardTokens.length; i++) {
            require(
                rewardAmounts[i] > 0,
                "StakingRewardsFactory::addRewardToken: reward amount should be greater than 0"
            );
            info.poolRewardToken.push(rewardTokens[i]);
            info.poolRewardAmount.push(rewardAmounts[i]);

            rewardTokenQuantities[rewardTokens[i]] = rewardAmounts[i];
        }
        stakingTokens.push(stakingToken);
    }

    // Rescue leftover funds from pool
    function rescueFunds(address stakingToken, address tokenAddress)
        public
        onlyOwner
    {
        StakingRewardsInfo storage info =
            stakingRewardsInfoByStakingToken[stakingToken];
        require(
            info.stakingRewards != address(0),
            "StakingRewardsFactory::notifyRewardAmount: not deployed"
        );
        StakingRewards(info.stakingRewards).rescueFunds(
            tokenAddress,
            msg.sender
        );
    }

    // Rescue leftover funds from factory
    function rescueFactoryFunds(address tokenAddress) public onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No balance for given token address");
        token.transfer(msg.sender, balance);
    }

    ///// permissionless functions

    // call notifyRewardAmount for all staking tokens.
    function notifyRewardAmounts() public {
        require(
            stakingTokens.length > 0,
            "StakingRewardsFactory::notifyRewardAmounts: called before any deploys"
        );
        for (uint256 i = 0; i < stakingTokens.length; i++) {
            notifyRewardAmount(stakingTokens[i]);
        }
    }

    // notify reward amount for an individual staking token.
    // this is a fallback in case the notifyRewardAmounts costs too much gas to call for all contracts
    function notifyRewardAmount(address stakingToken) public {
        // SWC-120-Weak Sources of Randomness from Chain Attributes: L122
        require(
            block.timestamp >= stakingRewardsGenesis,
            "StakingRewardsFactory::notifyRewardAmount: not ready"
        );

        StakingRewardsInfo storage info =
            stakingRewardsInfoByStakingToken[stakingToken];
        require(
            info.stakingRewards != address(0),
            "StakingRewardsFactory::notifyRewardAmount: not deployed"
        );
        for (uint256 i = 0; i < info.poolRewardToken.length; i++) {
            uint256 rewardAmount = info.poolRewardAmount[i];
            if (rewardAmount > 0) {
                info.poolRewardAmount[i] = 0;
                require(
                    IERC20(info.poolRewardToken[i]).transfer(
                        info.stakingRewards,
                        rewardAmount
                    ),
                    "StakingRewardsFactory::notifyRewardAmount: transfer failed"
                );
                StakingRewards(info.stakingRewards).notifyRewardAmount(
                    info.poolRewardToken[i],
                    rewardAmount
                );
            }
        }
    }

    function stakingRewardsInfo(address stakingToken)
        public
        view
        returns (
            address,
            address[] memory,
            uint256[] memory
        )
    {
        StakingRewardsInfo storage info =
            stakingRewardsInfoByStakingToken[stakingToken];
        return (
            info.stakingRewards,
            info.poolRewardToken,
            info.poolRewardAmount
        );
    }
}
