// SPDX-License-Identifier: https://github.com/lendroidproject/protocol.2.0/blob/master/LICENSE.md
pragma solidity 0.7.4;

import "@openzeppelin/contracts/math/SafeMath.sol";


/** @title Pacemaker
    @author Lendroid Foundation
    @notice Smart contract based on which various events in the Protocol take place
    @dev Audit certificate : Pending
*/


abstract contract Pacemaker {

    using SafeMath for uint256;

    // uint256 constant HEARTBEATSTARTTIME = 1607040000;// 2020-12-04 00:00:00 (UTC UTC +00:00)
    uint256 constant HEARTBEATSTARTTIME = 1602288000;// 2020-10-10 00:00:00 (UTC UTC +00:00)
    uint256 constant EPOCHPERIOD = 28800;// 8 hours
    uint256 constant WARMUPPERIOD = 2419200;// 28 days

    /**
        @notice Internal function to calculate current epoch value from the block timestamp
        @dev Calculates the nth 8-hour window frame since the heartbeat's start time
        @return uint256 : Current epoch value
    */
    function _currentEpoch() view internal returns (uint256) {
        if (block.timestamp > HEARTBEATSTARTTIME) {
            return block.timestamp.sub(HEARTBEATSTARTTIME).div(EPOCHPERIOD).add(1);
        }
        return 0;
    }

    /**
        @notice Displays the current epoch from internal function
        @dev External function
    */
    function currentEpoch() view external returns (uint256) {
        return _currentEpoch();
    }

}
