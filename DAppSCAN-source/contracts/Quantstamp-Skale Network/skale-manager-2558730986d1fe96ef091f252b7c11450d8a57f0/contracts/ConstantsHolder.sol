/*
    ConstantsHolder.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Artem Payvin

    SKALE Manager is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE Manager is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE Manager.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.5.16;

import "./Permissions.sol";
import "./interfaces/IConstants.sol";


/**
 * @title Contains constants and common variables for Skale Manager system
 * @author Artem Payvin
 */
contract ConstantsHolder is IConstants, Permissions {

    // initial price for creating Node (100 SKL)
    uint public constant NODE_DEPOSIT = 100 * 1e18;

    // part of Node for Tiny Skale-chain (1/128 of Node)
    uint8 public constant TINY_DIVISOR = 128;

    // part of Node for Small Skale-chain (1/8 of Node)
    uint8 public constant SMALL_DIVISOR = 8;

    // part of Node for Medium Skale-chain (full Node)
    uint8 public constant MEDIUM_DIVISOR = 1;

    // part of Node for Medium Test Skale-chain (1/4 of Node)
    uint8 public constant MEDIUM_TEST_DIVISOR = 4;

    // typically number of Nodes for Skale-chain (16 Nodes)
    uint public constant NUMBER_OF_NODES_FOR_SCHAIN = 16;

    // number of Nodes for Test Skale-chain (2 Nodes)
    uint public constant NUMBER_OF_NODES_FOR_TEST_SCHAIN = 2;

    // number of Nodes for Test Skale-chain (4 Nodes)
    uint public constant NUMBER_OF_NODES_FOR_MEDIUM_TEST_SCHAIN = 4;

    // 'Fractional' Part of ratio for create Fractional or Full Node
    uint public constant FRACTIONAL_FACTOR = 128;

    // 'Full' part of ratio for create Fractional or Full Node
    uint public constant FULL_FACTOR = 17;

    // number of second in one day
    uint32 public constant SECONDS_TO_DAY = 86400;

    // number of seconds in one month
    uint32 public constant SECONDS_TO_MONTH = 2592000;

    // number of seconds in one year
    uint32 public constant SECONDS_TO_YEAR = 31622400;

    // number of seconds in six years
    uint32 public constant SIX_YEARS = 186624000;

    // initial number of monitors
    uint public constant NUMBER_OF_MONITORS = 24;

    // MSR - Minimum staking requirement
    uint public msr;

    // Reward period - 30 days (each 30 days Node would be granted for bounty)
    uint32 public rewardPeriod;

    // Allowable latency - 150000 ms by default
    uint32 public allowableLatency;

    /**
     * Delta period - 1 hour (1 hour before Reward period became Monitors need
     * to send Verdicts and 1 hour after Reward period became Node need to come
     * and get Bounty)
     */
    uint32 public deltaPeriod;

    /**
     * Check time - 2 minutes (every 2 minutes monitors should check metrics
     * from checked nodes)
     */
    uint8 public checkTime;

    /**
     * Last time when system was underloaded
     * (allocations on Skale-chain / allocations on Nodes < 75%)
     */
    uint public lastTimeUnderloaded;

    /**
     * Last time when system was overloaded
     * (allocations on Skale-chain / allocations on Nodes > 85%)
     */
    uint public lastTimeOverloaded;

    //Need to add minimal allowed parameters for verdicts

    uint public launchTimestamp;

    uint public rotationDelay;

    uint public proofOfUseLockUpPeriodDays;

    /**
     * Set reward and delta periods to new one, run only by owner. This function
     * only for tests.
     * @param newRewardPeriod - new Reward period
     * @param newDeltaPeriod - new Delta period
     */
    function setPeriods(uint32 newRewardPeriod, uint32 newDeltaPeriod) external onlyOwner {
        rewardPeriod = newRewardPeriod;
        deltaPeriod = newDeltaPeriod;
    }

    /**
     * Set new check time. This function only for tests.
     * @param newCheckTime - new check time
     */
    function setCheckTime(uint8 newCheckTime) external onlyOwner {
        checkTime = newCheckTime;
    }

    /**
     * Set time if system underloaded, run only by NodesFunctionality contract
     */
    function setLastTimeUnderloaded() external allow("NodesFunctionality") {
        lastTimeUnderloaded = now;
    }

    /**
     * Set time if system iverloaded, run only by SchainsFunctionality contract
     */
    function setLastTimeOverloaded() external allow("SchainsFunctionality") {
        lastTimeOverloaded = now;
    }

    /**
     * Set latency new one in ms, run only by owner. This function
     * only for tests.
     * @param newAllowableLatency - new Allowable Latency
     */
    function setLatency(uint32 newAllowableLatency) external onlyOwner {
        allowableLatency = newAllowableLatency;
    }

    function setMSR(uint newMSR) external onlyOwner {
        msr = newMSR;
    }

    function setLaunchTimestamp(uint timestamp) external onlyOwner {
        launchTimestamp = timestamp;
    }

    function setRotationDelay(uint newDelay) external onlyOwner {
        rotationDelay = newDelay;
    }

    function setProofOfUseLockUpPeriod(uint periodDays) external onlyOwner {
        proofOfUseLockUpPeriodDays = periodDays;
    }

    /**
     * @dev constructor in Permissions approach
     * @param contractsAddress needed in Permissions constructor
     */
    function initialize(address contractsAddress) public initializer {
        Permissions.initialize(contractsAddress);

        msr = 5e6 * 1e18;
        rewardPeriod = 3600; // Test parameters
        allowableLatency = 150000; // Test parameters
        deltaPeriod = 300;  // Test parameters
        checkTime = 120; // Test parameters
        lastTimeUnderloaded = 0;
        lastTimeOverloaded = 0;
        launchTimestamp = now;
        rotationDelay = 12 hours;
        proofOfUseLockUpPeriodDays = 90;
    }
}
