/*
    MonitorsData.sol - SKALE Manager
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

import "./GroupsData.sol";


contract MonitorsData is GroupsData {


    struct Metrics {
        uint32 downtime;
        uint32 latency;
    }

    struct Monitor {
        uint nodeIndex;
        bytes32[] checkedNodes;
        Metrics[] verdicts;
    }

    mapping (bytes32 => bytes32[]) public checkedNodes;
    mapping (bytes32 => uint32[][]) public verdicts;

    /**
     *  Add checked node or update existing one if it is already exits
     */
    function addCheckedNode(bytes32 monitorIndex, bytes32 data) external allow(executorName) {
        uint indexLength = 14;
        require(data.length >= indexLength, "data is too small");
        for (uint i = 0; i < checkedNodes[monitorIndex].length; ++i) {
            require(checkedNodes[monitorIndex][i].length >= indexLength, "checked nodes data is too small");
            uint shift = (32 - indexLength).mul(8);
            bool equalIndex = checkedNodes[monitorIndex][i] >> shift == data >> shift;
            if (equalIndex) {
                checkedNodes[monitorIndex][i] = data;
                return;
            }
        }
        checkedNodes[monitorIndex].push(data);
    }

    function addVerdict(bytes32 monitorIndex, uint32 downtime, uint32 latency) external allow(executorName) {
        verdicts[monitorIndex].push([downtime, latency]);
    }

    function removeCheckedNode(bytes32 monitorIndex, uint indexOfCheckedNode) external allow(executorName) {
        if (indexOfCheckedNode != checkedNodes[monitorIndex].length - 1) {
            checkedNodes[monitorIndex][indexOfCheckedNode] = checkedNodes[monitorIndex][checkedNodes[monitorIndex].length - 1];
        }
        delete checkedNodes[monitorIndex][checkedNodes[monitorIndex].length - 1];
        checkedNodes[monitorIndex].length--;
    }

    function removeAllCheckedNodes(bytes32 monitorIndex) external allow(executorName) {
        delete checkedNodes[monitorIndex];
    }

    function removeAllVerdicts(bytes32 monitorIndex) external allow(executorName) {
        verdicts[monitorIndex].length = 0;
    }

    function getCheckedArray(bytes32 monitorIndex) external view returns (bytes32[] memory) {
        return checkedNodes[monitorIndex];
    }

    function getCheckedArrayLength(bytes32 monitorIndex) external view returns (uint) {
        return checkedNodes[monitorIndex].length;
    }

    function getLengthOfMetrics(bytes32 monitorIndex) external view returns (uint) {
        return verdicts[monitorIndex].length;
    }

    function initialize(address newContractsAddress) public initializer {
        GroupsData.initialize("MonitorsFunctionality", newContractsAddress);
    }
}
