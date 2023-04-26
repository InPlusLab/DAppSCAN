// SPDX-License-Identifier: MIT
pragma solidity 0.4.21;

/**
 * @title Codex Rewards
 * @author Paulo Felipe Barbosa
*/
contract ReentrancyGuard {
    /**
     * Booleans are more expensive than uint256 or any type that takes up a full
     * word because each write operation emits an extra SLOAD to first read the
     * slot's contents, replace the bits taken up by the boolean, and then write
     * back. This is the compiler's defense against contract upgrades and
     * pointer aliasing, and it cannot be disabled.

     * The values being non-zero value makes deployment a bit more expensive,
     * but in exchange the refund on every call to nonReentrant will be lower in
     * amount. Since refunds are capped to a percentage of the total
     * transaction's gas, it is best to keep them low in cases like this one, to
     * increase the likelihood of the full refund coming into effect.
     */
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    function ReentrancyGuard() internal {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        /// On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED);
        /// Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        /// By storing the original value once again, a refund is triggered (see
        /// https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

contract Owned {
    address public owner;
    address public nominatedOwner;

    function Owned(address _owner) public {
        require(_owner != address(0));
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function nominateNewOwner(address _owner) external onlyOwner {
        nominatedOwner = _owner;
        emit OwnerNominated(_owner);
    }

    function acceptOwnership() external {
        require(msg.sender == nominatedOwner);
        emit OwnerChanged(owner, nominatedOwner);
        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    modifier onlyOwner {
        _onlyOwner();
        _;
    }

    function _onlyOwner() private view {
        require(msg.sender == owner);
    }

    event OwnerNominated(address newOwner);
    event OwnerChanged(address oldOwner, address newOwner);
}

contract Pausable is Owned {
    uint256 public lastPauseTime;
    bool public paused;

    function Pausable() internal {
        /// This contract is abstract, and thus cannot be instantiated directly
        require(owner != address(0));
        /// Paused will be false, and lastPauseTime will be 0 upon initialisation
    }

    /**
     * @notice Change the paused state of the contract
     * @dev Only the contract owner may call this.
     */
    function setPaused(bool _paused) external onlyOwner {
        // Ensure we're actually changing the state before we do anything
        if (_paused == paused) {
            return;
        }

        // Set our paused state.
        paused = _paused;
        // If applicable, set the last pause time.
        if (paused) {
            lastPauseTime = now;
        }
        // Let everyone know that our pause state has changed.
        emit PauseChanged(paused);
    }

    event PauseChanged(bool isPaused);

    modifier notPaused {
        require(!paused);
        _;
    }
}

library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        /// Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        /// benefit is lost if 'b' is also tested.
        /// See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}

/// @dev Interface for the token contract to be referred
interface CDEXTokenContract {

    function balanceOf(address account) external view returns (uint256);
    function transfer(address _to, uint256 _value) external;
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);

}

/// @dev Interface for the ranking contract to be referred
interface CDEXRankingContract {

    function insert(uint _key, address _value) external;
    function remove(uint _key, address _value) external;

}

contract CDEXStakingPool is ReentrancyGuard, Pausable {
    using SafeMath for uint256;

    // STATE VARIABLES
    CDEXTokenContract public CDEXToken;
    CDEXRankingContract public CDEXRanking;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    
    /// Loyalty tiers are based on the user balance being staked
    uint256 public loyaltyTier1 = 100000000 * 1e8;
    uint256 public loyaltyTier2 = 10000000 * 1e8;
    uint256 public loyaltyTier3 = 1000000 * 1e8;
    
    /// Bonus tiers are calculated with precision of two decimals (i.e. 125 = 1.25%)
    uint256 public loyaltyTier1Bonus = 125;
    uint256 public loyaltyTier2Bonus = 100;
    uint256 public loyaltyTier3Bonus = 50;
    uint256 public depositedLoyaltyBonus;
    mapping(address=>uint256) public loyaltyBonuses;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    uint256 public depositedRewardTokens;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    uint256 public totalMembers;

    /// @notice Contract constructor. It's called as the contract is created.
    /// @param _owner The address of the contract owner. The owner will have
    ///               administrative privileges in the contract.
    /// @param _CDEXTokenContractAddress The address of the token contract.
    /// @param _rankingContractAddress The address of the ranking contract.
    function CDEXStakingPool(
        address _owner,
        address _CDEXTokenContractAddress,
        address _rankingContractAddress
    ) public Owned(_owner) {
        CDEXToken = CDEXTokenContract(_CDEXTokenContractAddress);
        CDEXRanking = CDEXRankingContract(_rankingContractAddress);
    }

    /// VIEWS
    
    /// @notice Returns the total staked tokens.
    /// @return Total value of staked tokens with full precision (8 zeroes)
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Returns the staked tokens balance for the informed address.
    /// @param account The address owning the balance
    /// @return Total value of staked tokens for the informed balance with full precision (8 zeroes)
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Returns the timestamp of when was the last time the rewards were applied.
    /// @return Timestamp of the current block or timestamp of the end of staking period.
    ///         Whichever is the earliest.
    function lastTimeRewardApplicable() public view returns (uint256) {
        return min(block.timestamp, periodFinish);
    }

    /// @return The value of tokens to be rewarded per staked token.
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e8)
                    .div(_totalSupply)
            );
    }

    /// @param account The address owning the accrued reward.
    /// @return The value of tokens currently accrued in the address' reward.
    function earned(address account) public view returns (uint256) {
        return
            _balances[account]
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e8)
                .add(rewards[account]);
    }

    /// @return The total reward to be distributed across the staking period.
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /// @return The smallest between informed values.
    /// @param a The first value to be compared
    /// @param b The second value to be compared
    function min(uint256 a, uint256 b) public pure returns (uint256) {
        return a < b ? a : b;
    }
    
    /// @return The minimum amounts for each one of the reward tiers.
    function getLoyaltyTiers() external view returns(uint256 tier1, uint256 tier2, uint256 tier3)
    {
        return(loyaltyTier1, loyaltyTier2, loyaltyTier3);
    }

    /// @notice The percentage is an integer representing a number with two decimal positions
    ///         e.g. 125 = 1.25%; 50 = 0.50%
    /// @return The bonus percentage of each reward tier.
    function getLoyaltyTiersBonus() external view returns(uint256 tier1Bonus, uint256 tier2Bonus, uint256 tier3Bonus)
    {
        return(loyaltyTier1Bonus, loyaltyTier2Bonus, loyaltyTier3Bonus);
    }

    // PUBLIC FUNCTIONS

    /// @notice Allows the users to stake tokens in the contract.
    /// @param amount The amount of tokens to be staked by the user.
    function stake(uint256 amount)
        external
        nonReentrant
        notPaused
        updateReward(msg.sender)
    {
        require(amount > 0);
        /// Increments the total staked balance
        _totalSupply = _totalSupply.add(amount);
        
        if(_balances[msg.sender] == 0) {
            /// Increments the totalMembers if the sending address didn't have any previous balance
            totalMembers += 1;
            /// Adds the user address to the ranking tree
            CDEXRanking.insert(amount, msg.sender);
        } else {
            /// Removes the user address from its current ranking node in the tree
            CDEXRanking.remove(_balances[msg.sender], msg.sender);
            /// Adds it again with the new value
            CDEXRanking.insert(_balances[msg.sender].add(amount), msg.sender);
        }
        /// Increments the sender's staked balance
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        /// Transfer the tokens from the sender's balance into the contract
        /// The amount needs to be previously approved in the token contract
        bool success = CDEXToken.transferFrom(msg.sender, address(this), amount);
        require(success);
        /// Emits the event
        emit Staked(msg.sender, amount);
    }

    /// @notice Withdraws the informed amount from the staked balance into the sender's address
    /// @param amount The amount of tokens to be withdrawn.
    function withdraw(uint256 amount)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0);
        /// Decrements the total staked balance
        _totalSupply = _totalSupply.sub(amount);
        /// Removes the user address from its current ranking node in the tree
        CDEXRanking.remove(_balances[msg.sender], msg.sender);
        /// Decrements the sender's staked balance
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        /// If the balance is zero after decremented, decrements the totalMembers
        if(_balances[msg.sender] == 0) {
            totalMembers -= 1;
        } else {
            /// If not, adds the user address back into the ranking tree with the new balance
            CDEXRanking.insert(_balances[msg.sender], msg.sender);
        }
        /// Transfers the tokens into the sender's address
        CDEXToken.transfer(msg.sender, amount);
        /// Emits the event
        emit Withdrawn(msg.sender, amount);
    }
    
    /// @notice Withdraws the reward accrued by the sender
    function getReward() 
        public 
        nonReentrant 
        updateReward(msg.sender) 
    {
        uint256 reward = rewards[msg.sender];
        /// Sanity checks
        if (reward > 0 && depositedRewardTokens >= reward) {
            uint256 loyaltyBonus = loyaltyBonuses[msg.sender];
            /// The withdraw is always for the full accrued reward amount
            rewards[msg.sender] = 0;
            loyaltyBonuses[msg.sender] = 0;
            /// Decrements the deposited reward tokens balance
            depositedRewardTokens = depositedRewardTokens.sub(reward);
            /// Decrements the deposited loyalty bonus balance
            depositedLoyaltyBonus = depositedLoyaltyBonus.sub(loyaltyBonus);
            /// Transfers the total accrued rewards plus the calculated bonus amount
            CDEXToken.transfer(msg.sender, reward.add(loyaltyBonus));
            /// Emits the event
            emit RewardPaid(msg.sender, reward);
            /// If any loytaly bonus was paid, emits the event
            if(loyaltyBonus > 0) {
                emit LoyaltyBonusPaid(msg.sender, loyaltyBonus);
            }
        }
    }

    /// @notice Allows the user to withdraw all accrued rewards and all the staked tokens at once
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }
    
    // RESTRICTED FUNCTIONS
    
    /// @notice Updates the instance of the Token contract
    /// @param _contractAddress The address of the contract where
    ///        the new instance will point to
    function setTokenContract(address _contractAddress) external onlyOwner {
        // Contract needs to be clean
        require(depositedRewardTokens == 0);
        CDEXToken = CDEXTokenContract(_contractAddress);
    }
    
    /// @notice Updates the instance of the Ranking contract
    /// @param _contractAddress The address of the contract where
    ///        the new instance will point to
    function setRankingContract(address _contractAddress) external onlyOwner {
        // Contract needs to be clean
        require(depositedRewardTokens == 0);
        CDEXRanking = CDEXRankingContract(_contractAddress);
    }
    
    /// @notice Allows the contract owner to add tokens to the contract balance.
    ///         This amount is not yet considered as a reward. For that the
    ///         notifyRewardAmount function needs to be executed.
    /// @param amount The value of tokens to be added to the balance.
    ///        To make it easier for the contract owner, the expected amount
    ///        does not consider the decimal places (without the 8 zeroes).
    function depositTokens(uint256 amount) public onlyOwner {
        /// Adding the decimal places to the amount
        amount = amount.mul(1e8);
        /// Calculating the total loyalty bonus percentage from the highest bonus tier
        uint256 loyaltyBonusFromAmount = amount.mul(loyaltyTier1Bonus).div(10000);
        /// Incrementing the total deposited loyalty bonus
        depositedLoyaltyBonus = depositedLoyaltyBonus.add(loyaltyBonusFromAmount);
        /// Increasing the total deposited tokens with the amount minus bonus
        depositedRewardTokens = depositedRewardTokens.add(amount.sub(loyaltyBonusFromAmount));
        /// Transferring the whole amount to the contract
        bool success = CDEXToken.transferFrom(owner, address(this), amount);
        require(success);
        /// Emits the event
        emit RewardsDeposited(owner, address(this), amount);
    }

    /// @notice Allows the contract owner to set up the reward amount for the staking period.
    /// @param reward The amount to be distributed between the stakers.
    ///        To make it easier for the contract owner, the expected amount
    ///        is in the integer format (without the 8 zeroes).
    function notifyRewardAmount(uint256 reward)
        public
        onlyOwner
        updateReward(address(0))
    {
        /// Adding the decimal places to the reward
        reward = reward.mul(1e8);
        /// The notified reward must be less then or equal to the total deposited rewards.
        require(reward <= depositedRewardTokens);
        /// If not during staking period, calculates the new reward rate per second.
        /// Else, adds the new reward to current non-distributed rewards.
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }
        /// Ensure the provided reward amount is not more than the balance in the contract.
        /// This keeps the reward rate in the right range, preventing overflows due to
        /// very high values of rewardRate in the earned and rewardsPerToken functions;
        /// Reward + leftover must be less than 2^256 / 10^8 to avoid overflow.
        require(rewardRate <= depositedRewardTokens.div(rewardsDuration));
        /// Updates the last updated time
        lastUpdateTime = block.timestamp;
        /// Resets the staking period
        periodFinish = block.timestamp.add(rewardsDuration);
        /// Emits the event
        emit RewardAdded(reward);
    }

    /// @notice Defines the duration, in seconds, for the staking period.
    ///         Once this value is defined, it cannot be changed until the period is finished.
    /// @param _rewardsDuration The duration in seconds for the staking period
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        /// Checks if the previously defined period has already finished
        require(block.timestamp > periodFinish);
        /// Updates the duration
        rewardsDuration = _rewardsDuration;
        /// Emits the event
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /// @notice Defines the minimum staked amount for each one of the loyalty tiers
    /// @param _loyaltyTier1 The minimum staked amount to be in Tier 1
    /// @param _loyaltyTier2 The minimum staked amount to be in Tier 2
    /// @param _loyaltyTier3 The minimum staked amount to be in Tier 3
    function setLoyaltyTiers(
        uint256 _loyaltyTier1, 
        uint256 _loyaltyTier2, 
        uint256 _loyaltyTier3
    ) external onlyOwner 
    {
        require(_loyaltyTier1 > _loyaltyTier2 && _loyaltyTier2 > _loyaltyTier3);
        /// Updates the tiers
        loyaltyTier1 = _loyaltyTier1.mul(1e8);
        loyaltyTier2 = _loyaltyTier2.mul(1e8);
        loyaltyTier3 = _loyaltyTier3.mul(1e8);
        /// Emits the event
        emit LoyaltyTiersUpdated(loyaltyTier1, loyaltyTier2, loyaltyTier3);
    }

    /// @notice Defines the bonus percentage for each one of the loyalty tiers
    ///         The percentage is an integer representing a number with two decimal positions
    ///         e.g. 125 = 1.25%; 50 = 0.50%
    /// @param _loyaltyTier1Bonus The bonus percentage for Tier 1
    /// @param _loyaltyTier2Bonus The bonus percentage for Tier 2
    /// @param _loyaltyTier3Bonus The bonus percentage for Tier 3
    function setLoyaltyTiersBonus(
        uint256 _loyaltyTier1Bonus, 
        uint256 _loyaltyTier2Bonus, 
        uint256 _loyaltyTier3Bonus
    ) external onlyOwner 
    {
        require(_loyaltyTier1Bonus > _loyaltyTier2Bonus && _loyaltyTier2Bonus > _loyaltyTier3Bonus);
        /// Total must be less than 100% of the reward
        /// Bonus tiers must be informed as two decimal precision, therefore 10,000 = 1 = 100%
        require(_loyaltyTier1Bonus.add(_loyaltyTier2Bonus).add(_loyaltyTier3Bonus) < 10000);
        /// Updates the tiers' bonus percentages
        loyaltyTier1Bonus = _loyaltyTier1Bonus;
        loyaltyTier2Bonus = _loyaltyTier2Bonus;
        loyaltyTier3Bonus = _loyaltyTier3Bonus;
        /// Emits the event
        emit LoyaltyTiersBonussUpdated(loyaltyTier1Bonus, loyaltyTier2Bonus, loyaltyTier3Bonus);
    }

    // MODIFIERS
    
    /// @notice Updates the accrued reward amount for the provided address
    /// @param account The address to have the balance updated
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            uint256 loyaltyBonus;
            uint256 previousRewards = rewards[account];
            rewards[account] = earned(account);
            // Calculates the reward earned since last time
            // to serve as a basis for the loyalty bonus calculation
            uint256 deltaRewards = rewards[account].sub(previousRewards);
            /// Defines the bonus amount based on the account's reward tier
            if (_balances[account] >= loyaltyTier1) {
                loyaltyBonus = deltaRewards.mul(loyaltyTier1Bonus).div(10000);
            } else if (_balances[account] >= loyaltyTier2) {
                loyaltyBonus = deltaRewards.mul(loyaltyTier2Bonus).div(10000);
            } else if (_balances[account] >= loyaltyTier3) {
                loyaltyBonus = deltaRewards.mul(loyaltyTier3Bonus).div(10000);
            }
            loyaltyBonuses[account] = loyaltyBonuses[account].add(loyaltyBonus);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // EVENTS

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event LoyaltyBonusPaid(address indexed user, uint256 loyaltyBonus);
    event RewardsDurationUpdated(uint256 newDuration);
    event RewardsDeposited(address sender, address receiver, uint256 reward);
    event LoyaltyTiersUpdated(uint256 loyaltyTier1, uint256 loyaltyTier2, uint256 loyaltyTier3);
    event LoyaltyTiersBonussUpdated(uint256 loyaltyTier1Bonus, uint256 loyaltyTier2Bonus, uint256 loyaltyTier3Bonus);
}