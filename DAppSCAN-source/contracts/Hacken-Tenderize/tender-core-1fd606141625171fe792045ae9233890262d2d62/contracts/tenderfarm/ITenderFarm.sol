// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../token/ITenderToken.sol";
import "../tenderizer/ITenderizer.sol";

/**
 * @title TenderFarm
 * @notice TenderFarm is responsible for incetivizing liquidity providers, by accepting LP Tokens
 * and a proportionaly rewarding them with TenderTokens over time.
 */
interface ITenderFarm {
    /**
     * @notice Farm gets emitted when an account stakes LP tokens.
     * @param account the account for which LP tokens were staked
     * @param amount the amount of LP tokens staked
     */
    event Farm(address indexed account, uint256 amount);

    /**
     * @notice Unfarm gets emitted when an account unstakes LP tokens.
     * @param account the account for which LP tokens were unstaked
     * @param amount the amount of LP tokens unstaked
     */
    event Unfarm(address indexed account, uint256 amount);

    /**
     * @notice Harvest gets emitted when an accounts harvests outstanding
     * rewards.
     * @param account the account which harvested rewards
     * @param amount the amount of rewards harvested
     */
    event Harvest(address indexed account, uint256 amount);

    /**
     * @notice RewardsAdded gets emitted when new rewards are added
     * and a new epoch begins
     * @param amount amount of rewards that were addedd
     */
    event RewardsAdded(uint256 amount);

    function initialize(
        IERC20 _stakeToken,
        ITenderToken _rewardToken,
        ITenderizer _tenderizer
    ) external returns (bool);

    /**
     * @notice stake liquidity pool tokens to receive rewards
     * @dev '_amount' needs to be approved for the 'TenderFarm' to transfer.
     * @dev harvests current rewards before accounting updates are made.
     * @param _amount amount of liquidity pool tokens to stake
     */
    function farm(uint256 _amount) external;

    /**
     * @notice allow spending token and stake liquidity pool tokens to receive rewards
     * @dev '_amount' needs to be approved for the 'TenderFarm' to transfer.
     * @dev harvests current rewards before accounting updates are made.
     * @dev calls permit on LP Token.
     * @param _amount amount of liquidity pool tokens to stake
     * @param _deadline deadline of the permit
     * @param _v v of signed Permit message
     * @param _r r of signed Permit message
     * @param _s s of signed Permit message
     */
    function farmWithPermit(
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    /**
     * @notice stake liquidity pool tokens for a specific account so that it receives rewards
     * @dev '_amount' needs to be approved for the 'TenderFarm' to transfer.
     * @dev staked tokens will belong to the account they are staked for.
     * @dev harvests current rewards before accounting updates are made.
     * @param _for account to stake for
     * @param _amount amount of liquidity pool tokens to stake
     */
    function farmFor(address _for, uint256 _amount) external;

    /**
     * @notice unstake liquidity pool tokens
     * @dev '_amount' needs to be approved for the 'TenderFarm' to transfer.
     * @dev harvests current rewards before accounting updates are made.
     * @param amount amount of liquidity pool tokens to stake
     */
    function unfarm(uint256 amount) external;

    /**
     * @notice harvest outstanding rewards
     * @dev reverts when trying to harvest multiple times if no new rewards have been added.
     * @dev emits an event with how many reward tokens have been harvested.
     */
    function harvest() external;

    /**
     * @notice add new rewards
     * @dev will 'start' a new 'epoch'.
     * @dev only callable by owner.
     * @param _amount amount of reward tokens to add
     */
    function addRewards(uint256 _amount) external;

    /**
     * @notice Check available rewards for an account.
     * @param _for address address of the account to check rewards for.
     * @return amount rewards for the provided account address.
     */
    function availableRewards(address _for) external view returns (uint256 amount);

    /**
     * @notice Check stake for an account.
     * @param _of address address of the account to check stake for.
     * @return amount LP tokens deposited for address
     */
    function stakeOf(address _of) external view returns (uint256 amount);

    /**
     * @notice Return the total amount of LP tokens staked in this farm.
     * @return stake total amount of LP tokens staked
     */
    function totalStake() external view returns (uint256 stake);

    /**
     * @notice Return the total amount of LP tokens staked
     * for the next reward epoch.
     * @return nextStake LP Tokens staked for next round
     */
    function nextTotalStake() external view returns (uint256 nextStake);

    /**
     * @notice Changes the tenderizer of the contract
     * @param _tenderizer address of the new tenderizer
     */
    function setTenderizer(ITenderizer _tenderizer) external;
}
