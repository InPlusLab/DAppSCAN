// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

import "../libs/MathUtils.sol";
pragma solidity 0.8.4;

/**
 * @title WithdrawalPools are used to batch user unlocks/withdrawals together
 * @notice These are used for protocols that do not support simultaneous unlocks
 */
library WithdrawalPools {
    struct Withdrawal {
        uint256 shares; // shares
        address receiver; // address of the receiver of this withdrawal, usually the caller of unlock
        uint256 epoch; // epoch at time of unlock
    }

    struct Pool {
        mapping(uint256 => Withdrawal) withdrawals; // key,value to keep track of withdrawals
        uint256 withdrawalID; // incrementor to keep track of the key for the 'withdrawals' mapping
        uint256 shares; // total outstanding shares of the unstake pool
        uint256 amount; // total amount of available tokens
        uint256 pendingUnlock; // amount of tokens to unlock
        uint256 pendingWithdrawal; // amount of tokens unlocked, pending withdrawal
        uint256 epoch; // current epoch start (e.g. incrementor or block number)
        uint256 lastEpoch; // last completed epoch (withdrawal completed)
    }

    function unlock(
        Pool storage _pool,
        address _receiver,
        uint256 _amount
    ) internal returns (uint256 withdrawalID) {
        withdrawalID = _pool.withdrawalID;

        uint256 shares = calcShares(_pool, _amount);

        _pool.withdrawals[withdrawalID] = Withdrawal({
            shares: shares,
            receiver: _receiver,
            epoch: _pool.epoch
        });

        _pool.pendingUnlock += _amount;

        _pool.shares += shares;

        _pool.withdrawalID++;
    }

    function withdraw(
        Pool storage _pool,
        uint256 _withdrawalID,
        address _account
    ) internal returns (uint256 withdrawAmount) {
        Withdrawal memory withdrawal = _pool.withdrawals[_withdrawalID];

        require(withdrawal.epoch < _pool.lastEpoch, "ONGOING_UNLOCK");
        require(_account == withdrawal.receiver, "ACCOUNT_MISTMATCH");

        withdrawAmount = calcAmount(_pool, withdrawal.shares);

        _pool.amount -= withdrawAmount;

        _pool.shares -= withdrawal.shares;

        delete _pool.withdrawals[_withdrawalID];
    }

    function processUnlocks(Pool storage _pool) internal returns (uint256 pendingUnlock_){
        require(_pool.epoch == _pool.lastEpoch, "ONGOING_UNLOCK");
        _pool.pendingWithdrawal += _pool.pendingUnlock;
        pendingUnlock_ = _pool.pendingUnlock;
        _pool.pendingUnlock = 0;
        _pool.epoch = block.number;
    }

    function processWihdrawal(Pool storage _pool, uint256 _received) internal {
        require(_pool.epoch > _pool.lastEpoch, "ONGOING_UNLOCK");
        _pool.amount += _received;
        _pool.pendingWithdrawal = 0;
        _pool.lastEpoch = _pool.epoch;
    }

    function updateTotalTokens(Pool storage _pool, uint256 _newAmount) internal {
        // calculate relative amounts to subtract from 'amount' and 'pendingUnlock'
        uint256 amount_ = _pool.amount;
        uint256 pendingUnlock_ = _pool.pendingUnlock;
        uint256 pendingWithdrawal = _pool.pendingWithdrawal;
        uint256 total = amount_ + pendingUnlock_ + pendingWithdrawal;
        if(total > 0) {
            _pool.amount = _newAmount * amount_ / total;
            _pool.pendingUnlock = _newAmount * pendingUnlock_ / total;
            _pool.pendingWithdrawal = _newAmount * pendingWithdrawal / total;
        }
    }

    function totalTokens(Pool storage _pool) internal view returns (uint256) {
        return  _pool.amount + _pool.pendingUnlock + _pool.pendingWithdrawal;
    }

    function getAmount(Pool storage _pool) internal view returns (uint256) {
        return  _pool.amount;
    }

    function epoch(Pool storage _pool) internal view returns (uint256) {
        return _pool.epoch;
    }

    function lastEpoch(Pool storage _pool) internal view returns (uint256) {
        return _pool.lastEpoch;
    }

    function getWithdrawal(Pool storage _pool, uint256 _withdrawalID)
        internal
        view
        returns (Withdrawal memory)
    {
        return _pool.withdrawals[_withdrawalID];
    }

    function calcShares(Pool storage _pool, uint256 _amount) internal view returns (uint256 shares) {
        uint256 totalTokens_ = totalTokens(_pool);
        uint256 totalShares = _pool.shares;

        if (totalTokens_ == 0) return _amount;

        if (totalShares == 0) return _amount;

        return MathUtils.percOf(_amount, totalShares, totalTokens_);
    }

    function calcAmount(Pool storage _pool, uint256 _shares) internal view returns (uint256) {
        uint256 totalShares = _pool.shares;
        if (totalShares == 0) return 0;

        return MathUtils.percOf(_shares, totalTokens(_pool), totalShares);
    }
}
