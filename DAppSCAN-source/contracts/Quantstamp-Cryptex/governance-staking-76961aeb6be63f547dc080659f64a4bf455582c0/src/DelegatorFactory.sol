// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/security/ReentrancyGuard.sol";
import "@openzeppelin/utils/math/SafeMath.sol";
import "./interfaces/IGovernanceToken.sol";
import "./Delegator.sol";
import "ds-test/test.sol";

/**
 * @title Delegator Contract Factory
 * @author Cryptex.Finance
 * @notice Contract in charge of generating Delegator contracts, handling delegations and CTX balance map, rewards.
 */

contract DelegatorFactory is Ownable, ReentrancyGuard, DSTest {
   /// @notice Using open zeppelin libraries
   using SafeMath for uint256;

   /* ========== STATE VARIABLES ========== */

   /// @notice Address of the staking governance token
   address public immutable stakingToken;

   /// @notice Address of the reward token
   address public immutable rewardsToken;

   /// @notice Minimum wait time before removing stake
   uint256 public waitTime;

   /// @notice Tracks the period where users stop earning rewards
   uint256 public periodFinish = 0;
   uint256 public rewardRate = 0;

   /// @notice How long the rewards lasts, it updates when more rewards are added
   uint256 public rewardsDuration = 186 days;

   /// @notice Last time rewards were updated
   uint256 public lastUpdateTime;

   /// @notice Amount of reward calculated per token stored
   uint256 public rewardPerTokenStored;

   /// @notice Track the rewards paid to users
   mapping(address => uint256) public userRewardPerTokenPaid;

   /// @notice Tracks the user rewards
   mapping(address => uint256) public rewards;

   /// @notice Tracks the address of a delegatee with a delegator contract address
   mapping(address => address) public delegatorToDelegatee;

   /// @notice Tracks the delegator contract address from delegatee address
   mapping(address => address) public delegateeToDelegator;

   /// @notice Tracks if address is an official delegator
   mapping(address => bool) public delegators;

   /// @notice Tracks minimum wait time the account has to wait before removing stake
   mapping(address => mapping(address => uint256)) public stakerWaitTime;

   /// @dev Tracks the total supply of staked tokens
   uint256 private _totalSupply;

   /// @dev Tracks the amount of staked tokens per user
   mapping(address => uint256) private _balances;

   /* ========== EVENTS ========== */

   /// @notice An event emitted when a Delegator is created
   event DelegatorCreated(address indexed delegator, address indexed delegatee);

   /// @notice An event emitted when an user has staked and delegated
   event Staked(
      address indexed delegator,
      address indexed delegatee,
      uint256 amount
   );

   /// @notice An event emitted when an user removes stake and undelegated
   event Withdrawn(
      address indexed delegator,
      address indexed delegatee,
      uint256 amount
   );

   /// @notice An event emitted when the minimum wait time is updated
   event WaitTimeUpdated(uint256 waitTime);

   /// @notice An event emitted when a reward is added
   event RewardAdded(uint256 reward);

   /// @notice An event emitted when reward is paid to a user
   event RewardPaid(address indexed user, uint256 reward);

   /// @notice An event emitted when the rewards duration is updated
   event RewardsDurationUpdated(uint256 newDuration);

   /* ========== CONSTRUCTOR ========== */

   /**
    * @notice Constructor
    * @param stakingToken_ address
    * @param rewardsToken_ address
    * @param waitTime_ uint256
    * @param timelock_ address
    * @dev transfers ownership to timelock
    */
   constructor(
      address stakingToken_,
      address rewardsToken_,
      uint256 waitTime_,
      address timelock_
   ) {
      stakingToken = stakingToken_;
      rewardsToken = rewardsToken_;
      waitTime = waitTime_;
      transferOwnership(timelock_);
   }

   /* ========== MODIFIERS ========== */

   /**
    * @notice Updates the reward and time on call.
    * @param account_ address
    */
   modifier updateReward(address account_) {
      rewardPerTokenStored = rewardPerToken();
      lastUpdateTime = lastTimeRewardApplicable();

      if (account_ != address(0)) {
         rewards[account_] = earned(account_);
         userRewardPerTokenPaid[account_] = rewardPerTokenStored;
      }
      _;
   }

   /* ========== MUTATIVE FUNCTIONS ========== */

   /**
    * @notice Notifies the contract that reward has been added to be given.
    * @param reward_ uint
    * @dev Only owner  can call it
    * @dev Increases duration of rewards
    */
   //  SWC-Requirement Violation: L147 - L174
   function notifyRewardAmount(uint256 reward_)
      external
      onlyOwner
      updateReward(address(0))
   {
      if (block.timestamp >= periodFinish) {
         rewardRate = reward_.div(rewardsDuration);
      } else {
         uint256 remaining = periodFinish.sub(block.timestamp);
         uint256 leftover = remaining.mul(rewardRate);
         rewardRate = reward_.add(leftover).div(rewardsDuration);
      }

      // Ensure the provided reward amount is not more than the balance in the contract.
      // This keeps the reward rate in the right range, preventing overflows due to
      // very high values of rewardRate in the earned and rewardsPerToken functions;
      // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
      uint256 balance = IGovernanceToken(rewardsToken).balanceOf(address(this));
      require(
         rewardRate <= balance.div(rewardsDuration),
         "Provided reward too high"
      );

      lastUpdateTime = block.timestamp;
      periodFinish = block.timestamp.add(rewardsDuration);
      emit RewardAdded(reward_);
   }

   /**
    * @notice  Updates the reward duration
    * @param rewardsDuration_ uint
    * @dev Only owner can call it
    * @dev Previous rewards must be complete
    */
   function setRewardsDuration(uint256 rewardsDuration_) external onlyOwner {
      require(
         block.timestamp > periodFinish,
         "Previous rewards period must be complete before changing the duration for the new period"
      );
      rewardsDuration = rewardsDuration_;
      emit RewardsDurationUpdated(rewardsDuration);
   }

   /**
    * @notice Transfers to the caller the current amount of rewards tokens earned.
    * @dev updates rewards on call
    */
   function getReward() external nonReentrant updateReward(msg.sender) {
      uint256 reward = rewards[msg.sender];
      if (reward > 0) {
         rewards[msg.sender] = 0;
         IGovernanceToken(rewardsToken).transfer(msg.sender, reward);
         emit RewardPaid(msg.sender, reward);
      }
   }

   /**
    * @notice Creates a new delegator contract that delegates all votes to delegatee_
    * @param delegatee_ address that will be receiving all votes
    * @dev only one delegator contract pointing to the same delegatee can exist
    */
   function createDelegator(address delegatee_) external {
      require(delegatee_ != address(0), "Delegatee can't be 0");
      require(
         delegateeToDelegator[delegatee_] == address(0),
         "Delegator already created"
      );
      Delegator delegator = new Delegator(delegatee_, stakingToken);
      delegateeToDelegator[delegatee_] = address(delegator);
      delegatorToDelegatee[address(delegator)] = delegatee_;
      delegators[address(delegator)] = true;
      emit DelegatorCreated(address(delegator), delegatee_);
   }

   /**
    * @notice Stakes to delegator_ the amount_ specified
    * @param delegator_ contract address where to send the amount_
    * @param amount_ uint to be staked and delegated
    * @dev Delegator must be valid and amount has to be greater than 0
    * @dev amount_ is transferred to the delegator contract and staker starts earning rewards if active
    * @dev updates rewards on call
    */
   function stake(address delegator_, uint256 amount_)
      external
      nonReentrant
      updateReward(msg.sender)
   {
      require(delegators[delegator_], "Not a valid delegator");
      require(amount_ > 0, "Amount must be greater than 0");
      _totalSupply = _totalSupply.add(amount_);
      _balances[msg.sender] = _balances[msg.sender].add(amount_);
      Delegator d = Delegator(delegator_);
      d.stake(msg.sender, amount_);
      stakerWaitTime[msg.sender][delegator_] = block.timestamp + waitTime;
      IGovernanceToken(stakingToken).transferFrom(
         msg.sender,
         delegator_,
         amount_
      );
      emit Staked(delegator_, msg.sender, amount_);
   }

   /**
    * @notice Removes amount_ from delegator_
    * @param delegator_ contract address where to remove the stake from
    * @param amount_ uint to be removed from stake and undelegated
    * @dev Delegator must be valid and amount has to be greater than 0
    * @dev amount_ must be <= that current user stake
    * @dev amount_ is transferred from the  delegator contract to the staker
    * @dev updates rewards on call
    * @dev requires that at least waitTime has passed since delegation to unDelegate
    */
   function withdraw(address delegator_, uint256 amount_)
      external
      nonReentrant
      updateReward(msg.sender)
   {
      require(delegators[delegator_], "Not a valid delegator");
      require(amount_ > 0, "Amount must be greater than 0");
      require(
         block.timestamp >= stakerWaitTime[msg.sender][delegator_],
         "Need to wait the minimum staking period"
      );
      _totalSupply = _totalSupply.sub(amount_);
      _balances[msg.sender] = _balances[msg.sender].sub(amount_);
      Delegator d = Delegator(delegator_);
      d.removeStake(msg.sender, amount_);
      emit Withdrawn(delegator_, msg.sender, amount_);
   }

   /**
    * @notice updates the min wait time between delegation and unDelegation
    * @param waitTime_ uint new wait time
    * @dev only the owner can call it
    */
   function updateWaitTime(uint256 waitTime_) external onlyOwner {
      waitTime = waitTime_;
      emit WaitTimeUpdated(waitTime_);
   }

   /* ========== VIEWS ========== */

   /// @notice Returns the total amount of staked tokens.
   function totalSupply() external view returns (uint256) {
      return _totalSupply;
   }

   /**
    * @notice Returns the amount of staked tokens from specific user
    * @param account_ address
    */
   function balanceOf(address account_) external view returns (uint256) {
      return _balances[account_];
   }

   /// @notice Returns reward rate for a duration
   function getRewardForDuration() external view returns (uint256) {
      return rewardRate.mul(rewardsDuration);
   }

   /// @notice Returns the minimum between current block timestamp or the finish period of rewards.
   function lastTimeRewardApplicable() public view returns (uint256) {
      return min(block.timestamp, periodFinish);
   }

   /// @notice Returns the calculated reward per token deposited.
   function rewardPerToken() public view returns (uint256) {
      if (_totalSupply == 0) {
         return rewardPerTokenStored;
      }

      return
         rewardPerTokenStored.add(
            lastTimeRewardApplicable()
               .sub(lastUpdateTime)
               .mul(rewardRate)
               .mul(1e18)
               .div(_totalSupply)
         );
   }

   /**
    * @notice Returns the amount of reward tokens a user has earned.
    * @param account_ address
    */
   function earned(address account_) public view returns (uint256) {
      return
         _balances[account_]
            .mul(rewardPerToken().sub(userRewardPerTokenPaid[account_]))
            .div(1e18)
            .add(rewards[account_]);
   }

   /**
    * @notice Returns the minimum between two variables
    * @param a_ uint
    * @param b_ uint
    */
   function min(uint256 a_, uint256 b_) public pure returns (uint256) {
      return a_ < b_ ? a_ : b_;
   }
}
