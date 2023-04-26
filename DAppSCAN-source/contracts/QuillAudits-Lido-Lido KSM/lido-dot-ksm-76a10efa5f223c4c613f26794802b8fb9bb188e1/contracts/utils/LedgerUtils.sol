// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../../interfaces/Types.sol";


library LedgerUtils {
    /// @notice Return unlocking and withdrawable balances
    function getTotalUnlocking(Types.OracleData memory report, uint64 _eraId) internal pure returns (uint128, uint128) {
        uint128 _total = 0;
        uint128 _withdrawble = 0;
        for (uint i = 0; i < report.unlocking.length; i++) {
            _total += report.unlocking[i].balance;
            if (report.unlocking[i].era <= _eraId) {
                _withdrawble += report.unlocking[i].balance;
            }
        }
        return (_total, _withdrawble);
    }
    /// @notice Return stash balance that can be freely transfer or allocated for stake
    function getFreeBalance(Types.OracleData memory report) internal pure returns (uint128) {
        return report.stashBalance - report.totalBalance;
    }

    /// @notice Return true if report is consistent
    function isConsistent(Types.OracleData memory report) internal pure returns (bool) {
        (uint128 _total,) = getTotalUnlocking(report, 0);
        return report.unlocking.length < type(uint8).max
            && report.totalBalance == (report.activeBalance + _total)
            && report.stashBalance >= report.totalBalance;
    }
}