// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import {IAccessControl, AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import "hardhat/console.sol";

import {StableThenToken} from "./staking/StableThenToken.sol";
import {IRewardParameters, RewardCalculator} from "./staking/RewardCalculator.sol";
import {ITalentToken} from "./TalentToken.sol";
import {ITalentFactory} from "./TalentFactory.sol";

/// Staking contract
///
/// @notice During phase 1, accepts USDT, which is automatically converted into an equivalent TAL amount.
///   Once phase 2 starts (after a TAL address has been set), only TAL deposits are accepted
///
/// @notice Staking:
///   Each stake results in minting a set supply of the corresponding talent token
///   Talent tokens are immediately transfered to the staker, and TAL is locked into the stake
///   If the amount of TAL sent corresponds to an amount of Talent Token greater than
///
/// @notice Checkpoints:
///   Any action on a stake triggers a checkpoint. Checkpoints accumulate
///   all rewards since the last checkpoint until now. A new stake amount is
///   calculated, and reward calculation starts again from the checkpoint's
///   timestamp.
///
/// @notice Unstaking:
///   By sending back an amount of talent token, you can recover an amount of
///   TAL previously staked (or earned through staking rewards), in proportion to
///   your stake and amount of talent tokens. e.g.: if you have a stake of 110 TAL
///   and have minted 2 Talent Tokens, sending 1 Talent Token gets you 55 TAL back.
///   This process also burns the sent Talent Token
///
/// @notice Re-stake:
///   Stakers can at any moment strengthen their position by sending in more TAL to an existing stake.
///   This will cause a checkpoint, accumulate rewards in the stake, and mint new Talent Token
///
/// @notice Claim rewards:
///   Stakers can, at any moment, claim whatever rewards are pending from their stake.
///   Rewards are only calculated from the moment of their last checkpoint.
///   Claiming rewards adds the calculated amount of TAL to the existing stake,
///   and mints the equivalent amount of Talent Token.
///
/// @notice Withdraw rewards:
///   Stakers can, at any moment, claim whatever rewards are pending from their stake.
///   Rewards are only calculated from the moment of their last checkpoint.
///   Withdrawing rewards sends the calculated amount of TAL to the staker's wallet.
///   No Talent Token is minted in this scenario
///
/// @notice Rewards:
///   given based on the logic from `RewardCalculator`, which
///   relies on a continuous `totalAdjustedShares` being updated on every
///   stake/withdraw. Seel `RewardCalculator` for more details
///
/// @notice Disabling staking:
///   The team reserves the ability to halt staking & reward accumulation,
///   to use if the tokenomics model or contracts don't work as expected, and need to be rethough.
///   In this event, any pending rewards must still be valid and redeemable by stakers.
///   New stakes must not be allowed, and existing stakes will not accumulate new rewards past the disabling block
///
/// @notice Withdrawing remaining rewards:
///   If staking is disabled, or if the end timestamp has been reached, the team can then
///   intervene on stakes to accumulate their rewards on their behalf, in order to reach an `activeStakes` count of 0.
///   Once 0 is reached, since no more claims will ever be made,
///   the remaining TAL from the reward pool can be safely withdrawn back to the team
contract Staking is AccessControl, StableThenToken, RewardCalculator, IERC1363Receiver {
    //
    // Begin: Declarations
    //

    /// Details of each individual stake
    struct StakeData {
        /// Amount currently staked
        uint256 tokenAmount;
        /// Talent tokens minted as part of this stake
        uint256 talentAmount;
        /// Latest checkpoint for this stake. Staking rewards should only be
        /// calculated from this moment forward. Anything past it should already
        /// be accounted for in `tokenAmount`
        uint256 lastCheckpointAt;
        uint256 S;
        bool finishedAccumulating;
    }

    /// Possible actions when a checkpoint is being triggered
    enum RewardAction {
        WITHDRAW,
        RESTAKE
    }

    //
    // Begin: Constants
    //

    bytes4 constant ERC1363_RECEIVER_RET = bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)"));

    //
    // Begin: State
    //

    /// List of all stakes (investor => talent => Stake)
    mapping(address => mapping(address => StakeData)) public stakes;

    // How many stakes are there in total
    uint256 public activeStakes;

    // How many stakes have finished accumulating rewards
    uint256 finishedAccumulatingStakeCount;

    /// Talent's share of rewards, to be redeemable by each individual talent
    mapping(address => uint256) public talentRedeemableRewards;

    /// Max S for a given talent, to halt rewards after minting is over
    mapping(address => uint256) public maxSForTalent;

    // Ability for admins to disable further stakes and rewards
    bool public disabled;

    /// The Talent Token Factory contract (ITalentFactory)
    address public factory;

    /// The price (in USD cents) of a single TAL token
    uint256 public tokenPrice;

    /// The price (in TAL tokens) of a single Talent Token
    uint256 public talentPrice;

    /// How much stablecoin was staked, but without yet depositing the expected TAL equivalent
    ///
    /// @notice After TAL is deployed, `swapStableForToken(uint256)` needs to be
    /// called by an admin, to withdraw any stable coin stored in the contract,
    /// and replace it with the TAL equivalent
    uint256 public totalStableStored;

    // How much TAL is currently staked (not including rewards)
    uint256 public totalTokensStaked;

    // How many has been withdrawn by the admin at the end of staking
    uint256 rewardsAdminWithdrawn;

    /// Sum of sqrt(tokenAmount) for each stake
    /// Used to compute adjusted reward values
    uint256 public override(IRewardParameters) totalAdjustedShares;

    // How much TAL is to be given in rewards
    uint256 public immutable override(IRewardParameters) rewardsMax;

    // How much TAL has already been given/reserved in rewards
    uint256 public override(IRewardParameters) rewardsGiven;

    /// Start date for staking period
    uint256 public immutable override(IRewardParameters) start;

    /// End date for staking period
    uint256 public immutable override(IRewardParameters) end;

    // Continuously growing value used to compute reward distributions
    uint256 public S;

    // Timestamp at which S was last updated
    uint256 public SAt;

    /// re-entrancy guard for `updatesAdjustedShares`
    bool private isAlreadyUpdatingAdjustedShares;

    //
    // Begin: Events
    //

    // emitted when a new stake is created
    event Stake(address indexed owner, address indexed talentToken, uint256 talAmount, bool stable);

    // emitte when stake rewards are reinvested into the stake
    event RewardClaim(address indexed owner, address indexed talentToken, uint256 stakerReward, uint256 talentReward);

    // emitted when stake rewards are withdrawn
    event RewardWithdrawal(
        address indexed owner,
        address indexed talentToken,
        uint256 stakerReward,
        uint256 talentReward
    );

    // emitted when a talent withdraws his share of rewards
    event TalentRewardWithdrawal(address indexed talentToken, address indexed talentTokenWallet, uint256 reward);

    // emitted when a withdrawal is made from an existing stake
    event Unstake(address indexed owner, address indexed talentToken, uint256 talAmount);

    //
    // Begin: Implementation
    //

    /// @param _start Timestamp at which staking begins
    /// @param _end Timestamp at which staking ends
    /// @param _rewardsMax Total amount of TAL to be given in rewards
    /// @param _stableCoin The USD-pegged stable-coin contract to use
    /// @param _factory ITalentFactory instance
    /// @param _tokenPrice The price of a tal token in the give stable-coin (50 means 1 TAL = 0.50USD)
    /// @param _talentPrice The price of a talent token in TAL (50 means 1 Talent Token = 50 TAL)
    constructor(
        uint256 _start,
        uint256 _end,
        uint256 _rewardsMax,
        address _stableCoin,
        address _factory,
        uint256 _tokenPrice,
        uint256 _talentPrice
    ) StableThenToken(_stableCoin) {
        require(_tokenPrice > 0, "_tokenPrice cannot be 0");
        require(_talentPrice > 0, "_talentPrice cannot be 0");

        start = _start;
        end = _end;
        rewardsMax = _rewardsMax;
        factory = _factory;
        tokenPrice = _tokenPrice;
        talentPrice = _talentPrice;
        SAt = _start;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// Creates a new stake from an amount of stable coin.
    /// The USD amount will be converted to the equivalent amount in TAL, according to the pre-determined rate
    ///
    /// @param _amount The amount of stable coin to stake
    /// @return true if operation succeeds
    ///
    /// @notice The contract must be previously approved to spend _amount on behalf of `msg.sender`
    function stakeStable(address _talent, uint256 _amount)
        public
        onlyWhileStakingEnabled
        stablePhaseOnly
        updatesAdjustedShares(msg.sender, _talent)
        returns (bool)
    {
        require(_amount > 0, "amount cannot be zero");
        require(!disabled, "staking has been disabled");

        uint256 tokenAmount = convertUsdToToken(_amount);

        totalStableStored += _amount;

        _checkpointAndStake(msg.sender, _talent, tokenAmount);

        IERC20(stableCoin).transferFrom(msg.sender, address(this), _amount);

        emit Stake(msg.sender, _talent, tokenAmount, true);

        return true;
    }

    /// Redeems rewards since last checkpoint, and reinvests them in the stake
    ///
    /// @param _talent talent token of the stake to process
    /// @return true if operation succeeds
    function claimRewards(address _talent) public returns (bool) {
        claimRewardsOnBehalf(msg.sender, _talent);

        return true;
    }

    /// Redeems rewards for a given staker, and reinvests them in the stake
    ///
    /// @param _owner owner of the stake to process
    /// @param _talent talent token of the stake to process
    /// @return true if operation succeeds
    function claimRewardsOnBehalf(address _owner, address _talent)
        public
        updatesAdjustedShares(_owner, _talent)
        returns (bool)
    {
        _checkpoint(_owner, _talent, RewardAction.RESTAKE);

        return true;
    }

    /// Redeems rewards since last checkpoint, and withdraws them to the owner's wallet
    ///
    /// @param _talent talent token of the stake to process
    /// @return true if operation succeeds
    function withdrawRewards(address _talent)
        public
        tokenPhaseOnly
        updatesAdjustedShares(msg.sender, _talent)
        returns (bool)
    {
        _checkpoint(msg.sender, _talent, RewardAction.WITHDRAW);

        return true;
    }

    /// Redeems a talent's share of the staking rewards
    ///
    /// @notice When stakers claim rewards, a share of those is reserved for
    ///   the talent to redeem for himself through this function
    ///
    /// @param _talent The talent token from which rewards are to be claimed
    /// @return true if operation succeeds
    function withdrawTalentRewards(address _talent) public tokenPhaseOnly returns (bool) {
        // only the talent himself can redeem their own rewards
        require(msg.sender == ITalentToken(_talent).talent(), "only the talent can withdraw their own shares");

        uint256 amount = talentRedeemableRewards[_talent];

        IERC20(token).transfer(msg.sender, amount);

        talentRedeemableRewards[_talent] = 0;

        return true;
    }

    /// Calculates stable coin balance of the contract
    ///
    /// @return the stable coin balance
    function stableCoinBalance() public view returns (uint256) {
        return IERC20(stableCoin).balanceOf(address(this));
    }

    /// Calculates TAL token balance of the contract
    ///
    /// @return the amount of TAL tokens
    function tokenBalance() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// Queries how much TAL can currently be staked on a given talent token
    ///
    /// @notice The limit of this value is enforced by the tokens' `mintingAvailability()`
    ///   (see `TalentToken` contract)
    ///
    /// @notice Stakes that exceed this amount will be rejected
    ///
    /// @param _talent Talent token to query
    /// @return How much TAL can be staked on the given talent token, before depleting minting supply
    function stakeAvailability(address _talent) public view returns (uint256) {
        require(_isTalentToken(_talent), "not a valid talent token");

        uint256 talentAmount = ITalentToken(_talent).mintingAvailability();

        return convertTalentToToken(talentAmount);
    }

    /// Deposits TAL in exchange for the equivalent amount of stable coin stored in the contract
    ///
    /// @notice Meant to be used by the contract owner to retrieve stable coin
    /// from phase 1, and provide the equivalent TAL amount expected from stakers
    ///
    /// @param _stableAmount amount of stable coin to be retrieved.
    ///
    /// @notice Corresponding TAL amount will be enforced based on the set price
    function swapStableForToken(uint256 _stableAmount) public onlyRole(DEFAULT_ADMIN_ROLE) tokenPhaseOnly {
        require(_stableAmount <= totalStableStored, "not enough stable coin left in the contract");

        uint256 tokenAmount = convertUsdToToken(_stableAmount);
        totalStableStored -= _stableAmount;

        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        IERC20(stableCoin).transfer(msg.sender, _stableAmount);
    }

    //
    // Begin: IERC1363Receiver
    //

    function onTransferReceived(
        address, // _operator
        address _sender,
        uint256 _amount,
        bytes calldata data
    ) external override(IERC1363Receiver) onlyWhileStakingEnabled returns (bytes4) {
        if (_isToken(msg.sender)) {
            require(!disabled, "staking has been disabled");

            // if input is TAL, this is a stake since TAL deposits are enabled when
            // `setToken` is called, no additional check for `tokenPhaseOnly` is
            // necessary here
            address talent = bytesToAddress(data);

            _checkpointAndStake(_sender, talent, _amount);

            emit Stake(_sender, talent, _amount, false);

            return ERC1363_RECEIVER_RET;
        } else if (_isTalentToken(msg.sender)) {
            require(_isTokenSet(), "TAL token not yet set. Refund not possible");

            // if it's a registered Talent Token, this is a refund
            address talent = msg.sender;

            uint256 tokenAmount = _checkpointAndUnstake(_sender, talent, _amount);

            emit Unstake(_sender, talent, tokenAmount);

            return ERC1363_RECEIVER_RET;
        } else {
            revert("Unrecognized ERC1363 token received");
        }
    }

    function _isToken(address _address) internal view returns (bool) {
        return _address == token;
    }

    function _isTalentToken(address _address) internal view returns (bool) {
        return ITalentFactory(factory).isTalentToken(_address);
    }

    //
    // End: IERC1363Receivber
    //

    //
    // Begin: IRewardParameters
    //

    function totalShares() public view override(IRewardParameters) returns (uint256) {
        return totalTokensStaked;
    }

    function rewardsLeft() public view override(IRewardParameters) returns (uint256) {
        return rewardsMax - rewardsGiven - rewardsAdminWithdrawn;
    }

    /// Panic button, if we decide to halt the staking process for some reason
    ///
    /// @notice This feature should halt further accumulation of rewards, and prevent new stakes from occuring
    /// Existing stakes will still be able to perform all usual operations on existing stakes.
    /// They just won't accumulate new TAL rewards (i.e.: they can still restake rewards and mint new talent tokens)
    function disable() public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!disabled, "already disabled");

        _updateS();
        disabled = true;
    }
    // SWC-116-Block values as a proxy for time: L444
    /// Allows the admin to withdraw whatever is left of the reward pool
    function adminWithdraw() public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(disabled || block.timestamp < end, "not disabled, and not end of staking either");
        require(activeStakes == 0, "there are still stakes accumulating rewards. Call `claimRewardsOnBehalf` on them");

        uint256 amount = rewardsLeft();
        require(amount > 0, "nothing left to withdraw");

        IERC20(token).transfer(msg.sender, amount);
        rewardsAdminWithdrawn += amount;
    }

    //
    // End: IRewardParameters
    //

    //
    // Private Interface
    //

    /// Creates a checkpoint, and then stakes adds the given TAL amount to the stake,
    ///   minting Talent token in the process
    ///
    /// @dev This function assumes tokens have been previously transfered by
    ///   the caller function or via `ERC1363Receiver` or `stableStake`
    ///
    /// @param _owner Owner of the stake
    /// @param _talent Talent token to stake on
    /// @param _tokenAmount TAL amount to stake
    function _checkpointAndStake(
        address _owner,
        address _talent,
        uint256 _tokenAmount
    ) private updatesAdjustedShares(_owner, _talent) {
        require(_isTalentToken(_talent), "not a valid talent token");
        require(_tokenAmount > 0, "amount cannot be zero");

        _checkpoint(_owner, _talent, RewardAction.RESTAKE);
        _stake(_owner, _talent, _tokenAmount);
    }

    /// Creates a checkpoint, and then unstakes the given TAL amount,
    ///   burning Talent token in the process
    ///
    /// @dev This function assumes tokens have been previously transfered by
    ///   the caller function or via `ERC1363Receiver` or `stableStake`
    ///
    /// @param _owner Owner of the stake
    /// @param _talent Talent token to uliasnstake from
    /// @param _talentAmount Talent token amount to unstake
    function _checkpointAndUnstake(
        address _owner,
        address _talent,
        uint256 _talentAmount
    ) private updatesAdjustedShares(_owner, _talent) returns (uint256) {
        require(_isTalentToken(_talent), "not a valid talent token");

        _checkpoint(_owner, _talent, RewardAction.RESTAKE);

        StakeData storage stake = stakes[_owner][_talent];

        require(stake.lastCheckpointAt > 0, "stake does not exist");
        require(stake.talentAmount >= _talentAmount);

        // calculate TAL amount proportional to how many talent tokens are
        // being deposited if stake has 100 deposited TAL + 1 TAL earned from
        // rewards, then returning 1 Talent Token should result in 50.5 TAL
        // being returned, instead of the 50 that would be given under the set
        // exchange rate
        uint256 proportion = (_talentAmount * MUL) / stake.talentAmount;
        uint256 tokenAmount = (stake.tokenAmount * proportion) / MUL;

        require(IERC20(token).balanceOf(address(this)) >= tokenAmount, "not enough TAL to fulfill request");

        stake.talentAmount -= _talentAmount;
        stake.tokenAmount -= tokenAmount;
        totalTokensStaked -= tokenAmount;

        // if stake is over, it has finished accumulating
        if (stake.tokenAmount == 0 && !stake.finishedAccumulating) {
            stake.finishedAccumulating = true;

            // also decrease the counter
            activeStakes -= 1;
        }

        _burnTalent(_talent, _talentAmount);
        _withdrawToken(_owner, tokenAmount);

        return tokenAmount;
    }

    /// Adds the given TAL amount to the stake, minting Talent token in the process
    ///
    /// @dev This function assumes tokens have been previously transfered by
    ///   the caller function or via `ERC1363Receiver` or `stableStake`
    ///
    /// @param _owner Owner of the stake
    /// @param _talent Talent token to stake on
    /// @param _tokenAmount TAL amount to stake
    function _stake(
        address _owner,
        address _talent,
        uint256 _tokenAmount
    ) private {
        uint256 talentAmount = convertTokenToTalent(_tokenAmount);

        StakeData storage stake = stakes[_owner][_talent];

        // if it's a new stake, increase stake count
        if (stake.tokenAmount == 0) {
            activeStakes += 1;
        }

        stake.tokenAmount += _tokenAmount;
        stake.talentAmount += talentAmount;

        totalTokensStaked += _tokenAmount;

        _mintTalent(_owner, _talent, talentAmount);
    }

    /// Performs a new checkpoint for a given stake
    ///
    /// Calculates all pending rewards since the last checkpoint, and accumulates them
    /// @param _owner Owner of the stake
    /// @param _talent Talent token staked
    /// @param _action Whether to withdraw or restake rewards
    function _checkpoint(
        address _owner,
        address _talent,
        RewardAction _action
    ) private updatesAdjustedShares(_owner, _talent) {
        StakeData storage stake = stakes[_owner][_talent];

        _updateS();

        // calculate rewards since last checkpoint
        address talentAddress = ITalentToken(_talent).talent();

        // if the talent token has been fully minted, rewards can only be
        // considered up until that timestamp (or S, according to the math)
        // so end date of reward is
        // truncated in that case
        //
        // this will enforce that rewards past this checkpoint will always be
        // 0, effectively ending the stake
        uint256 maxS = (maxSForTalent[_talent] > 0) ? maxSForTalent[_talent] : S;

        (uint256 stakerRewards, uint256 talentRewards) = calculateReward(
            stake.tokenAmount,
            stake.S,
            maxS,
            stake.talentAmount,
            IERC20(_talent).balanceOf(talentAddress)
        );

        rewardsGiven += stakerRewards + talentRewards;
        stake.S = maxS;
        stake.lastCheckpointAt = block.timestamp; // SWC-116-Block values as a proxy for time: L601

        talentRedeemableRewards[_talent] += talentRewards;

        // if staking is disabled, set token to finishedAccumulating, and decrease activeStakes
        // this forces admins to finish accumulation of all stakes, via `claimRewardsOnBehalf`
        // before withdrawing any remaining TAL from the reward pool
        if (disabled && !stake.finishedAccumulating) {
            stake.finishedAccumulating = true;
            activeStakes -= 1;
        }

        // no need to proceed if there's no rewards yet
        if (stakerRewards == 0) {
            return;
        }

        if (_action == RewardAction.WITHDRAW) {
            IERC20(token).transfer(_owner, stakerRewards);
            emit RewardWithdrawal(_owner, _talent, stakerRewards, talentRewards);
        } else if (_action == RewardAction.RESTAKE) {
            // truncate rewards to stake to the maximum stake availability
            uint256 availability = stakeAvailability(_talent);
            uint256 rewardsToStake = (availability > stakerRewards) ? stakerRewards : availability;
            uint256 rewardsToWithdraw = stakerRewards - rewardsToStake;

            _stake(_owner, _talent, rewardsToStake);
            emit RewardClaim(_owner, _talent, rewardsToStake, talentRewards);

            // TODO test
            // TODO the !!token part as well
            if (rewardsToWithdraw > 0 && token != address(0x0)) {
                IERC20(token).transfer(_owner, rewardsToWithdraw);
                emit RewardWithdrawal(_owner, _talent, rewardsToWithdraw, 0);
            }
        } else {
            revert("Unrecognized checkpoint action");
        }
    }

    function _updateS() private {
        if (disabled) {
            return;
        }

        if (totalTokensStaked == 0) {
            return;
        }
// SWC-116-Block values as a proxy for time: L650-L651
        S = S + (calculateGlobalReward(SAt, block.timestamp)) / totalAdjustedShares;
        SAt = block.timestamp;
    }

    function calculateEstimatedReturns(
        address _owner,
        address _talent,
        uint256 _currentTime
    ) public view returns (uint256 stakerRewards, uint256 talentRewards) {
        StakeData storage stake = stakes[_owner][_talent];
        uint256 newS;

        if (maxSForTalent[_talent] > 0) {
            newS = maxSForTalent[_talent];
        } else {
            newS = S + (calculateGlobalReward(SAt, _currentTime)) / totalAdjustedShares;
        }
        address talentAddress = ITalentToken(_talent).talent();
        uint256 talentBalance = IERC20(_talent).balanceOf(talentAddress);

        (uint256 sRewards, uint256 tRewards) = calculateReward(
            stake.tokenAmount,
            stake.S,
            newS,
            stake.talentAmount,
            talentBalance
        );

        return (sRewards, tRewards);
    }

    // function disable() {
    //     _updateS();
    //     disable = true;
    //     totalSharesWhenDisable = totalTokensStaked;

    //     reservedTAL = (sqrt(totalSharesWhenDisable) * (S - 0)) / MUL;
    //     availableTAL = rewardsMax() - reservedTAL;
    // }

    /// mints a given amount of a given talent token
    /// to be used within a staking update (re-stake or new deposit)
    ///
    /// @notice The staking update itself is assumed to happen on the caller
    function _mintTalent(
        address _owner,
        address _talent,
        uint256 _amount
    ) private {
        ITalentToken(_talent).mint(_owner, _amount);

        if (maxSForTalent[_talent] == 0 && ITalentToken(_talent).mintingFinishedAt() > 0) {
            maxSForTalent[_talent] = S;
        }
    }

    /// burns a given amount of a given talent token
    /// to be used within a staking update (withdrawal or refund)
    ///
    /// @notice The staking update itself is assumed to happen on the caller
    ///
    /// @notice Since withdrawal functions work via ERC1363 and receive the
    /// Talent token prior to calling `onTransferReceived`, /   by this point,
    /// the contract is the owner of the tokens to be burnt, not the owner
    function _burnTalent(address _talent, uint256 _amount) private {
        ITalentToken(_talent).burn(address(this), _amount);
    }

    /// returns a given amount of TAL to an owner
    function _withdrawToken(address _owner, uint256 _amount) private {
        IERC20(token).transfer(_owner, _amount);
    }

    modifier updatesAdjustedShares(address _owner, address _talent) {
        if (isAlreadyUpdatingAdjustedShares) {
            // works like a re-entrancy guard, to prevent sqrt calculations
            // from happening twice
            _;
        } else {
            isAlreadyUpdatingAdjustedShares = true;
            // calculate current adjusted shares for this stake
            // we don't deduct it directly because other computations wrapped by this modifier depend on the original value
            // (e.g. reward calculation)
            // therefore, we just keep track of it, and do a final update to the stored value at the end;
            // temporarily deduct from adjusted shares
            uint256 toDeduct = sqrt(stakes[_owner][_talent].tokenAmount);

            _;

            // calculated adjusted shares again, now with rewards included, and
            // excluding the previously computed amount to be deducted
            // (replaced by the new one)
            totalAdjustedShares = totalAdjustedShares + sqrt(stakes[_owner][_talent].tokenAmount) - toDeduct;
            isAlreadyUpdatingAdjustedShares = false;
        }
    }
// SWC-116-Block values as a proxy for time: L748-L749
    modifier onlyWhileStakingEnabled() {
        require(block.timestamp >= start, "staking period not yet started");
        require(block.timestamp <= end, "staking period already finished");
        _;
    }

    /// Converts a given USD amount to TAL
    ///
    /// @param _usd The amount of USD, in cents, to convert
    /// @return The converted TAL amount
    function convertUsdToToken(uint256 _usd) public view returns (uint256) {
        return (_usd / tokenPrice) * 1 ether;
    }

    /// Converts a given TAL amount to a Talent Token amount
    ///
    /// @param _tal The amount of TAL to convert
    /// @return The converted Talent Token amount
    function convertTokenToTalent(uint256 _tal) public view returns (uint256) {
        return (_tal / talentPrice) * 1 ether;
    }

    /// Converts a given Talent Token amount to TAL
    ///
    /// @param _talent The amount of Talent Tokens to convert
    /// @return The converted TAL amount
    function convertTalentToToken(uint256 _talent) public view returns (uint256) {
        return (_talent * talentPrice) / 1 ether;
    }

    /// Converts a given USD amount to Talent token
    ///
    /// @param _usd The amount of USD, in cents, to convert
    /// @return The converted Talent token amount
    function convertUsdToTalent(uint256 _usd) public view returns (uint256) {
        return convertTokenToTalent(convertUsdToToken(_usd));
    }

    /// Converts a byte sequence to address
    ///
    /// @dev This function requires the byte sequence to have 20 bytes of length
    ///
    /// @dev I didn't understand why using `calldata` instead of `memory` doesn't work,
    ///   or what would be the correct assembly to work with it.
    function bytesToAddress(bytes memory bs) private pure returns (address addr) {
        require(bs.length == 20, "invalid data length for address");

        assembly {
            addr := mload(add(bs, 20))
        }
    }
}
