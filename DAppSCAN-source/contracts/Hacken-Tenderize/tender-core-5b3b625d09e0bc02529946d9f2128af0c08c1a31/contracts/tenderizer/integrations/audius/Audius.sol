// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../libs/MathUtils.sol";
import "../../Tenderizer.sol";
import "../../WithdrawalPools.sol";
import "./IAudius.sol";

import { ITenderSwapFactory } from "../../../tenderswap/TenderSwapFactory.sol";

contract Audius is Tenderizer {
    using WithdrawalPools for WithdrawalPools.Pool;
    using SafeERC20 for IERC20;
    // Eventws for WithdrawalPool
    event ProcessUnstakes(address indexed from, address indexed node, uint256 amount);
    event ProcessWithdraws(address indexed from, uint256 amount);

    IAudius audius;

    address audiusStaking;

    WithdrawalPools.Pool withdrawPool;

    function initialize(
        IERC20 _steak,
        string calldata _symbol,
        IAudius _audius,
        address _node,
        uint256 _protocolFee,
        uint256 _liquidityFee,
        ITenderToken _tenderTokenTarget,
        TenderFarmFactory _tenderFarmFactory,
        ITenderSwapFactory _tenderSwapFactory
    ) external {
        Tenderizer._initialize(
            _steak,
            _symbol,
            _node,
            _protocolFee,
            _liquidityFee,
            _tenderTokenTarget,
            _tenderFarmFactory,
            _tenderSwapFactory
        );
        audius = _audius;
        audiusStaking = audius.getStakingAddress();
    }

    function _deposit(address _from, uint256 _amount) internal override {
        currentPrincipal += _amount;

        emit Deposit(_from, _amount);
    }

    function _stake(uint256 _amount) internal override {
        // Only stake available tokens that are not pending withdrawal
        uint256 amount = _amount;
        uint256 pendingWithdrawals = withdrawPool.getAmount();

        if (amount <= pendingWithdrawals) {
            return;
        }

        amount -= pendingWithdrawals;

        // Approve amount to Audius protocol
       steak.safeApprove(audiusStaking, amount);

        // stake tokens
        address _node = node;
        uint256 totalNewStake = audius.delegateStake(_node, amount);
        assert(totalNewStake >= amount);

        emit Stake(_node, amount);
    }

    function _unstake(
        address _account,
        address _node,
        uint256 _amount
    ) internal override returns (uint256 unstakeLockID) {
        uint256 amount = _amount;

        unstakeLockID =  withdrawPool.unlock(_account, amount);

        emit Unstake(_account, _node, amount, unstakeLockID);
    }

    function processUnstake() external onlyGov {
        uint256 amount = withdrawPool.processUnlocks();

        address node_ = node;

        // Undelegate from audius
        audius.requestUndelegateStake(node_, amount);

        emit ProcessUnstakes(msg.sender, node_, amount);
    }

    function _withdraw(address _account, uint256 _withdrawalID) internal override {
        uint256 amount = withdrawPool.withdraw(_withdrawalID, _account);
        // Transfer amount from unbondingLock to _account
        steak.safeTransfer(_account, amount);

        emit Withdraw(_account, amount, _withdrawalID);
    }

    function processWithdraw() external onlyGov {
        uint256 balBefore = steak.balanceOf(address(this));

        audius.undelegateStake();

        uint256 balAfter = steak.balanceOf(address(this));
        uint256 amount = balAfter - balBefore;

        withdrawPool.processWihdrawal(amount);

        emit ProcessWithdraws(msg.sender, amount);
    }

    function _claimRewards() internal override {
        // Process the rewards for the nodes that we have staked to
        try audius.claimRewards(node) {} catch {}

        // Get the new total delegator stake
        uint256 stake = audius.getTotalDelegatorStake(address(this));

        _processNewStake(stake);
    }

    function _processNewStake(uint256 _newStake) internal override {
        uint256 currentPrincipal_ = currentPrincipal;

        // adjust current token balance for potential protocol specific taxes or staking fees
        uint256 currentBal = _calcDepositOut(steak.balanceOf(address(this)));

        // calculate what the new currentPrinciple would be after the call
        // but excluding fees, pending unlocks and pending user withdrawals from rewards
        // which still need to be calculated if stake >= currentPrincipal
        uint256 stake_ = _newStake +
            currentBal -
            withdrawPool.amount -
            withdrawPool.pendingUnlock -
            pendingFees -
            pendingLiquidityFees;

        // Difference is negative, no rewards have been earnt
        // So no fees are charged
        if (stake_ <= currentPrincipal_) {
            currentPrincipal = stake_;
            uint256 diff = currentPrincipal_ - stake_;

            emit RewardsClaimed(-int256(diff), stake_, currentPrincipal_);

            // calculate amount to subtract relative to current principal
            uint256 unstakePoolTokens = withdrawPool.totalTokens();
            uint256 totalTokens = unstakePoolTokens + currentPrincipal_;
            if (totalTokens == 0) return;

            uint256 unstakePoolSlash = (diff * unstakePoolTokens) / totalTokens;
            withdrawPool.updateTotalTokens(unstakePoolTokens - unstakePoolSlash);

            return;
        }

        // Difference is positive, calculate the rewards
        uint256 totalRewards = stake_ - currentPrincipal_;

        // calculate the protocol fees
        uint256 fees = MathUtils.percOf(totalRewards, protocolFee);
        pendingFees += fees;

        // calculate the liquidity provider fees
        uint256 liquidityFees = MathUtils.percOf(totalRewards, liquidityFee);
        pendingLiquidityFees += liquidityFees;

        stake_ = stake_ - fees - liquidityFees;
        currentPrincipal = stake_;

        emit RewardsClaimed(int256(stake_ - currentPrincipal_), stake_, currentPrincipal_);
    }

    function _setStakingContract(address _stakingContract) internal override {
        emit GovernanceUpdate(
            "STAKING_CONTRACT",
            abi.encode(audius),
            abi.encode(_stakingContract)
        );
        audius = IAudius(_stakingContract);
        audiusStaking = audius.getStakingAddress();
    }
}
