// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

import "../libs/MathUtils.sol";
pragma solidity 0.8.4;

/**
 * @notice WithdrawalLocks are used to "proxy" user unlocks/withdrawals to the underlying contracts
 */
library WithdrawalLocks {

    struct WithdrawLock {
        uint256 amount;
        address account;
    }

    struct Locks {
        mapping(uint256 => WithdrawLock) withdrawals;
        uint256 nextWithdrawLockID;
    }

    function unlock(
        Locks storage _lock,
        address _receiver,
        uint256 _amount
    ) internal returns (uint256 withdrawalLockID) {
        withdrawalLockID = _lock.nextWithdrawLockID;
        
        _lock.nextWithdrawLockID = withdrawalLockID + 1;
        
        _lock.withdrawals[withdrawalLockID] = WithdrawLock({ amount: _amount, account: _receiver });
    }

    function withdraw(
        Locks storage _lock,
        address _account,
        uint256 _withdrawalLockID
    ) internal returns (uint256 amount) {
        WithdrawLock storage lock = _lock.withdrawals[_withdrawalLockID];
        address account = lock.account;
        amount = lock.amount;
        
        require(account == _account, "ACCOUNT_MISTMATCH");
        
        delete _lock.withdrawals[_withdrawalLockID];
    }
}
