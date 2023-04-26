/*
    ManagerData.sol - SKALE Manager
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

pragma solidity ^0.5.3;

import "./Permissions.sol";
import "./interfaces/IManagerData.sol";


/**
 * @title ManagerData - Data contract for SkaleManager
 */
contract ManagerData is IManagerData, Permissions {

    // miners capitalization
    uint public minersCap;
    // start time
    uint32 public startTime;
    // time of current stage
    uint32 public stageTime;
    // amount of Nodes at current stage
    uint public stageNodes;

    //name of executor contract
    string executorName;

    /**
     * @dev constuctor in Permissions approach
     * @param newExecutorName - name of executor contract
     * @param newContractsAddress needed in Permissions constructor
     */
    constructor(string memory newExecutorName, address newContractsAddress) Permissions(newContractsAddress) public {
        startTime = uint32(block.timestamp);
        executorName = newExecutorName;
    }

    /**
     * @dev setMinersCap - sets miners capitalization
     */
    function setMinersCap(uint newMinersCap) external allow(executorName) {
        minersCap = newMinersCap;
    }

    /**
     * @dev setStageTimeAndStageNodes - sets new stage time and new amount of Nodes at this stage
     */
    function setStageTimeAndStageNodes(uint newStageNodes) external allow(executorName) {
        stageNodes = newStageNodes;
        stageTime = uint32(block.timestamp);
    }

}
