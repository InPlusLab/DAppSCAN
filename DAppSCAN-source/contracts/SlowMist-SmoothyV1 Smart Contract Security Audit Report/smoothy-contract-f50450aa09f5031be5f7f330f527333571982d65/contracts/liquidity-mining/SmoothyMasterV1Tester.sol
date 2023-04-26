// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../liquidity-mining/SmoothyMasterV1.sol";


contract SmoothyMasterV1Tester is SmoothyMasterV1 {

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
        uint256 _pid,
        uint256 _amount,
        uint256 _end,
        uint256 _timestamp
    )
        external
        increasingTimestamp(_timestamp)
    {
        _createLock(_pid, _amount, _end, _timestamp);
    }

    function claimTest(uint256 _pid, address _account, uint256 _timestamp)
        public
        claimSmty(_pid, _account, _timestamp)
        // solium-disable-next-line
        increasingTimestamp(_timestamp) {
    }

}