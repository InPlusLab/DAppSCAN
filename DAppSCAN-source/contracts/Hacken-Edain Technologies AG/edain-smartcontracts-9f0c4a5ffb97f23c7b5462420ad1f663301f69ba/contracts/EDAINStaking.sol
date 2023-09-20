// SPDX-License-Identifier: MIT
// SWC-103-Floating Pragma: L3
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract EDAINStaking is Initializable, ERC20Upgradeable {
    using SafeMathUpgradeable for uint256;
    /**
     * @notice A stake struct is used to represent the way we store stakes,
     * A Stake will contain the users address, the amount staked and a timestamp,
     * timestamp which is when the stake was made
     * claimable the amount that can be claimed
     */
    struct Stake {
        address user;
        uint256 amount;
        uint256 timestamp;
        uint256 claimable;
    }

    /**
     * @notice Stakeholder is a staker that has active stakes
     */
    struct Stakeholder {
        address user;
        Stake[] address_stakes;
    }

    /**
     * @notice StakingSummary is a struct that is used to contain all stakes performed by a certain account
     */
    struct StakingSummary {
        uint256 total_amount;
        Stake[] stakes;
    }

    uint256 internal maxInterestRate;

    Stakeholder[] internal stakeholders;

    mapping(address => uint256) internal stakes;

    /**
     * @notice Staked event is triggered whenever a user stakes tokens, address is indexed to make it filterable
     */
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 index,
        uint256 timestamp
    );

    function __EDAINStaking_init() public initializer {
        // This push is needed so we avoid index 0 causing bug of index-1
        stakeholders.push();

        // 10% anual interest rate
        maxInterestRate = uint256(10**17);
    }

    /**
     * @notice _Stake is used to make a stake for an sender. It will remove the amount staked from the stakers account and
     * place those tokens inside a stake container StakeID
     */
    function _stake(uint256 _amount) internal {
        // Simple check so that user does not stake 0
        require(_amount > 0, "Cannot stake nothing");

        uint256 index = stakes[msg.sender];
        uint256 timestamp = block.timestamp;
        // See if the staker already has a staked index or if its the first time
        if (index == 0) {
            // This stakeholder stakes for the first time
            // We need to add him to the stakeHolders and also map it into the Index of the stakes
            // The index returned will be the index of the stakeholder in the stakeholders array
            index = _addStakeholder(msg.sender);
        }

        // Use the index to push a new Stake
        // push a newly created Stake with the current block timestamp.
        stakeholders[index].address_stakes.push(
            Stake(msg.sender, _amount, timestamp, 0)
        );
        // Emit an event that the stake has occured
        emit Staked(msg.sender, _amount, index, timestamp);
    }

    /**
     * @notice _addStakeholder takes care of adding a stakeholder to the stakeholders array
     */
    function _addStakeholder(address staker) internal returns (uint256) {
        // Push an empty item to the Array to make space for our new stakeholder
        stakeholders.push();
        // Calculate the index of the last item in the array by Len-1
        uint256 userIndex = stakeholders.length - 1;
        // Assign the address to the new index
        stakeholders[userIndex].user = staker;
        // Add index to the stakeHolders
        stakes[staker] = userIndex;
        return userIndex;
    }

    /**
     * @notice A simple method that calculates the rewards for each stakeholder.
     * @param _current_stake Stake struct with info
     * @return uint256 reward amount
     */
    function _calculateStakeReward(Stake memory _current_stake)
        internal
        view
        returns (uint256)
    {
        // Get the number of days since the stake is active
        uint256 _coinAge = (block.timestamp - _current_stake.timestamp).div(
            1 days
        );
        if (_coinAge <= 0) return 0;

        uint256 interest = _getAnnualInterest();
        uint256 currentReward = _coinAge * interest * _current_stake.amount;
        uint256 yearlyReward = 365 * 10**18;

        return currentReward / yearlyReward;
    }

    function _getAnnualInterest() internal view returns (uint256) {
        return maxInterestRate;
    }

    /**
     * @notice withdrawStake takes in an amount and an index of the stake and will remove tokens from that stake
     * Notice index of the stake is the users stake counter, starting at 0 for the first stake
     * Will return the amount to MINT into the acount
     * Will also calculateStakeReward and reset timer
     */
    function _withdrawStake(uint256 amount, uint256 index)
        internal
        returns (uint256)
    {
        // Grab user_index which is the index to use to grab the Stake[]
        uint256 user_index = stakes[msg.sender];
        Stake memory current_stake = stakeholders[user_index].address_stakes[
            index
        ];
        require(
            current_stake.amount >= amount,
            "Staking: Cannot withdraw more than you have staked"
        );

        // Calculate available Reward first before we start modifying data
        uint256 reward = _calculateStakeReward(current_stake);
        // Remove by subtracting the money unstaked
        current_stake.amount = current_stake.amount - amount;
        // If stake is empty, 0, then remove it from the array of stakes
        if (current_stake.amount == 0) {
            delete stakeholders[user_index].address_stakes[index];
        } else {
            // If not empty then replace the value of it
            stakeholders[user_index]
                .address_stakes[index]
                .amount = current_stake.amount;
            // Reset timer of stake
            stakeholders[user_index].address_stakes[index].timestamp = block
                .timestamp;
        }

        return amount + reward;
    }

    /**
     * @notice a method that will itterate trough stakes for an account
     * @param _staker the staker address
     * @return StakingSummary with total staked amount, stakeed amount and available rewards
     */
    function hasStake(address _staker)
        external
        view
        returns (StakingSummary memory)
    {
        // totalStakeAmount is used to count total staked amount of the address
        uint256 totalStakeAmount;
        // Keep a summary in memory since we need to calculate this
        StakingSummary memory summary = StakingSummary(
            0,
            stakeholders[stakes[_staker]].address_stakes
        );
        // Itterate all stakes and grab amount of stakes
        for (uint256 s = 0; s < summary.stakes.length; s += 1) {
            uint256 availableReward = _calculateStakeReward(summary.stakes[s]);
            summary.stakes[s].claimable = availableReward;
            totalStakeAmount += summary.stakes[s].amount;
        }
        // Assign calculate amount to summary
        summary.total_amount = totalStakeAmount;
        return summary;
    }
}
