// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../liquidity-mining/VotingEscrow.sol";


contract VotingEscrowTester is VotingEscrow {

    uint256 public lastTimestamp;

    modifier increasingTimestamp(uint256 _timestamp) {
        require (lastTimestamp <= _timestamp, "timestamp must be increasing");
        lastTimestamp = _timestamp;
        _;
    }

    /********************************************************
     * Code for testing purpose, should never be used in prod
     *********************************************************/
    function createLockTest(
        uint256 amount,
        uint256 end,
        uint256 timestamp
    )
        external
        increasingTimestamp(timestamp)
    {
        _createLock(amount, end, timestamp);
    }

    function extendLockTest(uint256 end, uint256 timestamp)
        external
        increasingTimestamp(timestamp)
    {
        _extendLock(end, timestamp);
    }
}