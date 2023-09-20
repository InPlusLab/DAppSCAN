// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../libs/MathUtils.sol";

import "../../Tenderizer.sol";
import "./IMatic.sol";

import "../../WithdrawalLocks.sol";

import { ITenderSwapFactory } from "../../../tenderswap/TenderSwapFactory.sol";

contract Matic is Tenderizer {
    using WithdrawalLocks for WithdrawalLocks.Locks;

    // Matic exchange rate precision
    uint256 constant EXCHANGE_RATE_PRECISION = 100; // For Validator ID < 8
    uint256 constant EXCHANGE_RATE_PRECISION_HIGH = 10**29; // For Validator ID >= 8

    // Matic stakeManager address
    address maticStakeManager;

    // Matic ValidatorShare
    IMatic matic;

    WithdrawalLocks.Locks withdrawLocks;

    function initialize(
        IERC20 _steak,
        string calldata _symbol,
        address _matic,
        address _node,
        uint256 _protocolFee,
        uint256 _liquidityFee,
        ITenderToken _tenderTokenTarget,
        TenderFarmFactory _tenderFarmFactory,
        ITenderSwapFactory _tenderSwapFactory
    ) public {
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
        maticStakeManager = _matic;
        matic = IMatic(_node);
    }

    function setNode(address _node) external override onlyGov {
        require(_node != address(0), "ZERO_ADDRESS");
        node = _node;
        matic = IMatic(_node);

        emit GovernanceUpdate("NODE");
    }

    function _deposit(address _from, uint256 _amount) internal override {
        currentPrincipal += _amount;

        emit Deposit(_from, _amount);
    }

    function _stake(address _node, uint256 _amount) internal override {
        // if no amount is specified, stake all available tokens
        uint256 amount = _amount;

        if (amount == 0) {
            return;
            // TODO: revert ?
        }

        // if no _node is specified, return
        if (_node == address(0)) {
            return;
        }

        // use default validator share contract if _node isn't specified
        IMatic matic_ = matic;
        // SWC-135-Code With No Effects: L88 - L90
        if (_node != address(0)) {
            matic_ = IMatic(_node);
        }

        // approve tokens
        // SWC-104-Unchecked Call Return Value: L93
        steak.approve(maticStakeManager, amount);

        // stake tokens
        uint256 min = ((amount * _getExchangeRatePrecision(matic_)) / _getExchangeRate(matic_)) - 1;
        matic_.buyVoucher(amount, min);

        emit Stake(address(matic_), amount);
    }

    function _unstake(
        address _account,
        address _node,
        uint256 _amount
    ) internal override returns (uint256 withdrawalLockID) {
        uint256 amount = _amount;

        // use default validator share contract if _node isn't specified
        IMatic matic_ = IMatic(_node);

        uint256 exhangeRatePrecision = _getExchangeRatePrecision(matic_);
        uint256 fxRate = _getExchangeRate(matic_);

        // Sanity check. Controller already checks user deposits and withdrawals > 0
        if (_account != gov) require(amount > 0, "ZERO_AMOUNT");
        if (amount == 0) {
            uint256 shares = matic_.balanceOf(address(this));
            amount = (shares * fxRate) / exhangeRatePrecision;
            require(amount > 0, "ZERO_STAKE");
        }

        currentPrincipal -= amount;

        // Unbond tokens
        uint256 max = ((amount * exhangeRatePrecision) / fxRate) + 1;
        matic_.sellVoucher_new(amount, max);

        // Manage Livepeer unbonding locks
        withdrawalLockID = withdrawLocks.unlock(_account, amount);

        emit Unstake(_account, address(matic_), amount, withdrawalLockID);
    }

    function _withdraw(address _account, uint256 _withdrawalID) internal override {
        withdrawLocks.withdraw(_account, _withdrawalID);

        // Check for any slashes during undelegation
        uint256 balBefore = steak.balanceOf(address(this));
        matic.unstakeClaimTokens_new(_withdrawalID);
        uint256 balAfter = steak.balanceOf(address(this));
        uint256 amount = balAfter >= balBefore ? balAfter - balBefore : 0;
        require(amount > 0, "ZERO_AMOUNT");

        // Transfer amount from unbondingLock to _account
        // SWC-104-Unchecked Call Return Value: L147
        steak.transfer(_account, amount);

        emit Withdraw(_account, amount, _withdrawalID);
    }

    function _claimRewards() internal override {
        // restake to compound rewards
        try matic.restake() {} catch {}

        uint256 shares = matic.balanceOf(address(this));
        uint256 stake = (shares * _getExchangeRate(matic)) / _getExchangeRatePrecision(matic);

        Tenderizer._processNewStake(stake);
    }

    function _setStakingContract(address _stakingContract) internal override {
        maticStakeManager = _stakingContract;

        emit GovernanceUpdate("STAKING_CONTRACT");
    }

    function _getExchangeRatePrecision(IMatic _matic) internal view returns (uint256) {
        return _matic.validatorId() < 8 ? EXCHANGE_RATE_PRECISION : EXCHANGE_RATE_PRECISION_HIGH;
    }

    function _getExchangeRate(IMatic _matic) internal view returns (uint256) {
        uint256 rate = _matic.exchangeRate();
        return rate == 0 ? 1 : rate;
    }
}
