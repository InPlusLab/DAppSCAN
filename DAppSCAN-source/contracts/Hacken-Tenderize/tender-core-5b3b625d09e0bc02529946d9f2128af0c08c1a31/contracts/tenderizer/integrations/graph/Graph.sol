// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../libs/MathUtils.sol";

import "../../Tenderizer.sol";
import "../../WithdrawalPools.sol";
import "./IGraph.sol";

import { ITenderSwapFactory } from "../../../tenderswap/TenderSwapFactory.sol";

contract Graph is Tenderizer {
    using WithdrawalPools for WithdrawalPools.Pool;
    using SafeERC20 for IERC20;

    // Eventws for WithdrawalPool
    event ProcessUnstakes(address indexed from, address indexed node, uint256 amount);
    event ProcessWithdraws(address indexed from, uint256 amount);

    // 100% in parts per million
    uint32 private constant MAX_PPM = 1000000;

    IGraph graph;

    WithdrawalPools.Pool withdrawPool;

    function initialize(
        IERC20 _steak,
        string calldata _symbol,
        IGraph _graph,
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
        graph = _graph;
    }

    function _calcDepositOut(uint256 _amountIn) internal view override returns (uint256) {
        return _amountIn - ((uint256(graph.delegationTaxPercentage()) * _amountIn) / MAX_PPM);
    }

    function _deposit(address _from, uint256 _amount) internal override {
        currentPrincipal += _calcDepositOut(_amount);

        emit Deposit(_from, _amount);
    }

    function _stake(uint256 _amount) internal override {
        // Only stake available tokens that are not pending withdrawal
        uint256 amount = _amount;
        uint256 pendingWithdrawals = withdrawPool.getAmount();

        // This check also validates 'amount - pendingWithdrawals' > 0
        if (amount <= pendingWithdrawals) {
            return;
        }

        amount -= pendingWithdrawals;

        // approve amount to Graph protocol
        steak.safeApprove(address(graph), amount);

        // stake tokens
        address _node = node;
        uint256 delegatedShares = graph.delegate(_node, amount);
        assert(delegatedShares > 0);

        emit Stake(_node, amount);
    }

    function _unstake(
        address _account,
        address _node,
        uint256 _amount
    ) internal override returns (uint256 unstakeLockID) {
        uint256 amount = _amount;

        unstakeLockID = withdrawPool.unlock(_account, amount);

        emit Unstake(_account, _node, amount, unstakeLockID);
    }

    function processUnstake() external onlyGov {
        uint256 amount = withdrawPool.processUnlocks();

        address node_ = node;

        // Calculate the amount of shares to undelegate
        IGraph.DelegationPool memory delPool = graph.delegationPools(node_);

        uint256 totalShares = delPool.shares;
        uint256 totalTokens = delPool.tokens;

        uint256 shares = (amount * totalShares) / totalTokens;

        // Shares =  amount * totalShares / totalTokens
        // undelegate shares
        graph.undelegate(node_, shares);

        emit ProcessUnstakes(msg.sender, node_, amount);
    }

    function _withdraw(address _account, uint256 _withdrawalID) internal override {
        uint256 amount = withdrawPool.withdraw(_withdrawalID, _account);

        // Transfer amount from unbondingLock to _account
        try steak.transfer(_account, amount) {} catch {
            // Account for roundoff errors in shares calculations
            uint256 steakBal = steak.balanceOf(address(this));
            if (amount > steakBal) {
                steak.safeTransfer(_account, steakBal);
            }
        }

        emit Withdraw(_account, amount, _withdrawalID);
    }

    function processWithdraw() external onlyGov {
        uint256 balBefore = steak.balanceOf(address(this));

        graph.withdrawDelegated(node, address(0));

        uint256 balAfter = steak.balanceOf(address(this));
        uint256 amount = balAfter - balBefore;

        withdrawPool.processWihdrawal(amount);

        emit ProcessWithdraws(msg.sender, amount);
    }

    function _claimRewards() internal override {
        IGraph.Delegation memory delegation = graph.getDelegation(node, address(this));
        IGraph.DelegationPool memory delPool = graph.delegationPools(node);

        uint256 delShares = delegation.shares;
        uint256 totalShares = delPool.shares;
        uint256 totalTokens = delPool.tokens;

        if (totalShares == 0) return;

        uint256 stake = (delShares * totalTokens) / totalShares;

        _processNewStake(stake);
    }

    function _processNewStake(uint256 _newStake) internal override {
        // TODO: all of the below could be a general internal function in Tenderizer.sol
        uint256 currentPrincipal_ = currentPrincipal;

        // adjust current token balance for potential protocol specific taxes or staking fees
        uint256 toBeStaked = _calcDepositOut(steak.balanceOf(address(this)) - withdrawPool.amount);

        // calculate what the new currentPrinciple would be after the call
        // but excluding fees from rewards for this rebase
        // which still need to be calculated if stake >= currentPrincipal
        uint256 stake_ = _newStake + toBeStaked - withdrawPool.pendingUnlock - pendingFees - pendingLiquidityFees;

        // Difference is negative, no rewards have been earnt
        // So no fees are charged
        if (stake_ <= currentPrincipal_) {
            currentPrincipal = stake_;
            uint256 diff = currentPrincipal_ - stake_;
            // calculate amount to subtract relative to current principal
            uint256 totalUnstakePoolTokens = withdrawPool.totalTokens();
            uint256 totalTokens = totalUnstakePoolTokens + currentPrincipal_;
            if (totalTokens == 0) return;

            uint256 unstakePoolSlash = (diff * totalUnstakePoolTokens) / totalTokens;
            withdrawPool.updateTotalTokens(totalUnstakePoolTokens - unstakePoolSlash);

            emit RewardsClaimed(-int256(diff), stake_, currentPrincipal_);

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
            abi.encode(graph),
            abi.encode(_stakingContract)
        );
        graph = IGraph(_stakingContract);
    }
}
