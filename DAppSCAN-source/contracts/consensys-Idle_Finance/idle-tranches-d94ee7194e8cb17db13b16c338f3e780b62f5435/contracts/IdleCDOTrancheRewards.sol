// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IIdleCDOTrancheRewards.sol";
import "./interfaces/IIdleCDO.sol";

import "./IdleCDOTrancheRewardsStorage.sol";
import "hardhat/console.sol";

/// @title IdleCDOTrancheRewards
/// @dev Contract used for staking specific tranche tokens and getting incentive rewards
contract IdleCDOTrancheRewards is Initializable, PausableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IIdleCDOTrancheRewards, IdleCDOTrancheRewardsStorage {
  using SafeERC20Upgradeable for IERC20Detailed;

  /// @notice Initialize the contract
  /// @param _trancheToken tranche address
  /// @param _rewards The rewards tokens
  /// @param _owner The owner of the contract
  /// @param _idleCDO The CDO where the reward tokens come from
  /// @param _governanceRecoveryFund address where rewards will be sent in case of transferToken call
  function initialize(
    address _trancheToken, address[] memory _rewards, address _owner,
    address _idleCDO, address _governanceRecoveryFund, uint256 _coolingPeriod
  ) public initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    PausableUpgradeable.__Pausable_init();

    transferOwnership(_owner);

    idleCDO = _idleCDO;
    tranche = _trancheToken;
    rewards = _rewards;
    governanceRecoveryFund = _governanceRecoveryFund;
    coolingPeriod = _coolingPeriod;
  }

  /// @notice Stake _amount of tranche token
  /// @param _amount The amount of tranche tokens to stake
  function stake(uint256 _amount) external whenNotPaused override {
    usersStakeBlock[msg.sender] = block.number;
    // update user index for each reward
    _updateUserIdx(msg.sender, _amount);
    usersStakes[msg.sender] += _amount;
    IERC20Detailed(tranche).safeTransferFrom(msg.sender, address(this), _amount);
    totalStaked += _amount;
  }

  /// @notice Unstake _amount of tranche tokens
  /// @param _amount The amount to unstake
  function unstake(uint256 _amount) external nonReentrant override {
    require(usersStakeBlock[msg.sender] + coolingPeriod < block.number, "COOLING_PERIOD");

    if (paused()) {
      // If the contract is paused, "unstake" will skip the claim of the rewards,
      // and those rewards won't be claimable in the future.
      address reward;
      for (uint256 i = 0; i < rewards.length; i++) {
        reward = rewards[i];
        usersIndexes[msg.sender][reward] = rewardsIndexes[reward];
      }
    } else {
      // Claim all rewards accrued
      _claim();
    }

    // if _amount is greater than usersStakes[msg.sender], the next line fails
    usersStakes[msg.sender] -= _amount;
    IERC20Detailed(tranche).safeTransfer(msg.sender, _amount);
    totalStaked -= _amount;
  }

  /// @notice Sends all the expected rewards to the msg.sender
  /// @dev User index is reset
  function claim() whenNotPaused nonReentrant external {
    _claim();
  }

  /// @notice Claim all rewards, used by claim and unstake
  function _claim() internal {
    address[] memory _rewards = rewards;
    for (uint256 i = 0; i < _rewards.length; i++) {
      address reward = _rewards[i];
      uint256 amount = expectedUserReward(msg.sender, reward);
      uint256 balance = IERC20Detailed(reward).balanceOf(address(this));
      if (amount > balance) {
        amount = balance;
      }
      // Set the user address equal to the global one
      usersIndexes[msg.sender][reward] = rewardsIndexes[reward];
      IERC20Detailed(reward).safeTransfer(msg.sender, amount);
    }
  }

  /// @notice Calculates the expected rewards for a user
  /// @param user The user address
  /// @param reward The reward token address
  /// @return The expected reward amount
  function expectedUserReward(address user, address reward) public view returns(uint256) {
    require(_includesAddress(rewards, reward), "!SUPPORTED");
    return ((rewardsIndexes[reward] - usersIndexes[user][reward]) * usersStakes[user]) / ONE_TRANCHE_TOKEN;
  }

  /// @notice Called by the CDO to deposit rewards
  /// @param _reward The rewards token address
  /// @param _amount The amount to deposit
  function depositReward(address _reward, uint256 _amount) external override {
    require(msg.sender == idleCDO, "!AUTH");
    require(_includesAddress(rewards, _reward), "!SUPPORTED");
    // Get rewards from CDO
    IERC20Detailed(_reward).safeTransferFrom(msg.sender, address(this), _amount);
    if (totalStaked > 0) {
      // rewards are splitted among all stakers
      rewardsIndexes[_reward] += _amount * ONE_TRANCHE_TOKEN / totalStaked;
    }
  }
  /// @notice It sets the coolingPeriod value
  /// @param _newCoolingPeriod The new cooling period
  function setCoolingPeriod(uint256 _newCoolingPeriod) external onlyOwner {
    coolingPeriod = _newCoolingPeriod;
  }

  /// @notice Update user indexes based on the amount being staked
  /// @param _user The user who is staking
  /// @param _amountToStake The amound staked
  function _updateUserIdx(address _user, uint256 _amountToStake) internal {
    address[] memory _rewards = rewards;
    uint256 userIndex;
    address reward;
    uint256 _currStake = usersStakes[_user];

    for (uint256 i = 0; i < _rewards.length; i++) {
      reward = _rewards[i];
      if (_currStake == 0) {
        // Set the user address equal to the global one
        usersIndexes[_user][reward] = rewardsIndexes[reward];
      } else {
        userIndex = usersIndexes[_user][reward];
        // Calculate the new user idx
        usersIndexes[_user][reward] = userIndex + (
          _amountToStake * (rewardsIndexes[reward] - userIndex) / (_currStake + _amountToStake)
        );
      }
    }
  }

  /// @dev this method is only used to check whether a token is an incentive tokens or not
  /// in the harvest call. The maximum number of element in the array will be a small number (eg at most 3-5)
  /// @param _array array of addresses to search for an element
  /// @param _val address of an element to find
  /// @return flag if the _token is an incentive token or not
  function _includesAddress(address[] memory _array, address _val) internal pure returns (bool) {
    for (uint256 i = 0; i < _array.length; i++) {
      if (_array[i] == _val) {
        return true;
      }
    }
    // explicit return to fix linter
    return false;
  }

  // Emergency method, funds gets transferred to the governanceRecoveryFund address
  function transferToken(address token, uint256 value) external onlyOwner nonReentrant returns (bool) {
    require(token != address(0), 'Address is 0');
    IERC20Detailed(token).safeTransfer(governanceRecoveryFund, value);
    return true;
  }
  /// @notice can be called by both the owner and the guardian
  /// @dev Pauses deposits and redeems
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice can be called by both the owner and the guardian
  /// @dev Unpauses deposits and redeems
  function unpause() external onlyOwner {
    _unpause();
  }
}
